require "test_helper"

class Metrics::MetaAnalyticsSyncTest < ActiveSupport::TestCase
  class FakeClient
    attr_reader :requests

    def initialize
      @requests = []
    end

    def get(path, params: {})
      @requests << [ path, params ]
      case path
      when "ig-123"
        { "id" => "ig-123", "name" => "Build Toronto", "username" => "build_toronto" }
      when "ig-123/media"
        { "data" => [ {
          "id" => "media-456",
          "caption" => "Hello Toronto",
          "media_type" => "IMAGE",
          "permalink" => "https://www.instagram.com/p/example/",
          "timestamp" => "2026-08-10T12:00:00+0000"
        } ] }
      when "ig-123/insights"
        insight_response(params.fetch(:metric).split(","), "2026-08-12T00:00:00+0000")
      when "media-456/insights"
        insight_response(params.fetch(:metric).split(","), nil)
      else
        raise "Unexpected request: #{path}"
      end
    end

    private

    def insight_response(names, end_time)
      { "data" => names.map.with_index do |name, index|
        entry = { "value" => index + 10 }
        entry["end_time"] = end_time if end_time
        { "name" => name, "period" => "day", "values" => [ entry ] }
      end }
    end
  end

  class TotalValueClient < FakeClient
    def get(path, params: {})
      return super unless path == "ig-123/insights" && params[:metric_type] == "total_value"

      # Record here too, so tests can assert on the day scoping of these requests.
      requests << [ path, params ]
      { "data" => params.fetch(:metric).split(",").map do |name|
        { "name" => name, "period" => "day", "total_value" => { "value" => 42 } }
      end }
    end
  end

  class BreakdownClient < TotalValueClient
    def get(path, params: {})
      return super unless path == "ig-123/insights" &&
        params[:metric] == "follows_and_unfollows"

      requests << [ path, params ]
      {
        "data" => [ {
          "name" => "follows_and_unfollows",
          "period" => "day",
          "total_value" => {
            "breakdowns" => [ {
              "dimension_keys" => [ "follow_type" ],
              "results" => [
                { "dimension_values" => [ "FOLLOWER" ], "value" => 17 },
                { "dimension_values" => [ "NON_FOLLOWER" ], "value" => 3 }
              ]
            } ]
          }
        } ]
      }
    end
  end

  class PaidOrganicClient < TotalValueClient
    def get(path, params: {})
      return super unless path == "ig-123/insights" && params[:breakdown] == "media_product_type"

      requests << [ path, params ]
      {
        "data" => params.fetch(:metric).split(",").map do |name|
          {
            "name" => name,
            "period" => "day",
            "total_value" => {
              "value" => 100,
              "breakdowns" => [ {
                "dimension_keys" => [ "media_product_type" ],
                "results" => [
                  { "dimension_values" => [ "POST" ], "value" => 70 },
                  { "dimension_values" => [ "REEL" ], "value" => 20 },
                  { "dimension_values" => [ "AD" ], "value" => 10 }
                ]
              } ]
            }
          }
        end
      }
    end
  end

  test "stores normalized Instagram analytics and complete source payloads" do
    now = Time.zone.parse("2026-08-12 13:00:00")
    client = FakeClient.new

    sync = Metrics::MetaAnalyticsSync.new(client: client, now: now)
    account = sync.sync_account!(
      platform: "instagram",
      account_key: "build_toronto",
      platform_account_id: "ig-123",
      account_metrics: %w[views reach]
    )
    sync.discover_recent_media!(account)

    assert_equal "build_toronto", account.username
    assert_equal now, account.last_synced_at
    assert_equal "ig-123", account.source_payload["id"]
    assert_equal 2, account.insights.count
    assert_equal 10, account.insights.find_by!(metric_name: "views").value_numeric

    medium = account.media.sole
    assert_equal "Hello Toronto", medium.caption
    assert_equal "media-456", medium.source_payload["id"]
    assert_equal Time.zone.parse("2026-08-10T12:00:00+0000"), medium.next_insights_sync_at
    refute client.requests.any? { |path, _params| path == "media-456/insights" }
    media_request = client.requests.find { |path, _params| path == "ig-123/media" }
    refute media_request.last.key?(:since)

    sync.sync_media_insights!(medium, metric_names: %w[likes comments])
    assert_equal 2, medium.insights.count
    assert_equal now, medium.insights.find_by!(metric_name: "likes").observed_at

    sync.sync_media_insights!(medium, metric_names: %w[likes comments])
    assert_equal 2, medium.insights.count
  end

  test "rejects accounts outside the configured allowlist" do
    error = assert_raises(ArgumentError) do
      Metrics::MetaAnalyticsSync.new(client: FakeClient.new).sync_account!(
        platform: "instagram",
        account_key: "unknown",
        platform_account_id: "ig-123"
      )
    end

    assert_match "Unsupported instagram account", error.message
  end

  test "separates Instagram total-value metrics and normalizes their values" do
    now = Time.zone.parse("2026-08-12 13:00:00")
    account = Metrics::MetaAnalyticsSync.new(client: TotalValueClient.new, now: now).sync_account!(
      platform: "instagram",
      account_key: "build_toronto",
      platform_account_id: "ig-123",
      account_metrics: %w[reach views accounts_engaged]
    )

    assert_equal 42, account.insights.find_by!(metric_name: "views").value_numeric
    assert_equal 42, account.insights.find_by!(metric_name: "accounts_engaged").value_numeric
  end

  test "day-scoped total-value metrics are dated by the requested day, not the sync clock" do
    now = Time.zone.parse("2026-08-20 02:30:00")
    client = TotalValueClient.new
    sync = Metrics::MetaAnalyticsSync.new(client: client, now: now, time_zone: "America/Los_Angeles")
    zone = ActiveSupport::TimeZone["America/Los_Angeles"]

    account = sync.sync_account!(
      platform: "instagram",
      account_key: "build_toronto",
      platform_account_id: "ig-123",
      account_metrics: %w[views],
      days: [ Date.new(2026, 8, 17), Date.new(2026, 8, 18) ]
    )

    observed = account.insights.where(metric_name: "views").order(:observed_at).pluck(:observed_at)
    # Meta stamps a day with the end of that day, so Aug 17 lands on Aug 18 00:00.
    assert_equal [ zone.parse("2026-08-18"), zone.parse("2026-08-19") ], observed
    refute observed.include?(now), "observed_at must never fall back to the sync clock"

    total_requests = client.requests.select { |_path, params| params[:metric_type] == "total_value" }
    assert_equal 2, total_requests.length
    since, untl = total_requests.first.last.values_at(:since, :until)
    assert_equal zone.parse("2026-08-17").to_i, since
    assert_equal zone.parse("2026-08-18").to_i - 1, untl
  end

  test "normalizes follower breakdowns into numeric follows and unfollows" do
    account = Metrics::MetaAnalyticsSync.new(
      client: BreakdownClient.new,
      now: Time.zone.parse("2026-08-20 02:30:00"),
      time_zone: "America/Los_Angeles"
    ).sync_account!(
      platform: "instagram",
      account_key: "build_toronto",
      platform_account_id: "ig-123",
      account_metrics: %w[follows_and_unfollows],
      days: [ Date.new(2026, 8, 17) ]
    )

    assert_equal 17, account.insights.find_by!(metric_name: "follows").value_numeric
    assert_equal 3, account.insights.find_by!(metric_name: "unfollows").value_numeric
    refute account.insights.exists?(metric_name: "follows_and_unfollows")
  end

  test "normalizes media product breakdowns into paid and organic properties" do
    account = Metrics::MetaAnalyticsSync.new(
      client: PaidOrganicClient.new,
      now: Time.zone.parse("2026-08-20 02:30:00"),
      time_zone: "America/Los_Angeles"
    ).sync_account!(
      platform: "instagram",
      account_key: "build_toronto",
      platform_account_id: "ig-123",
      account_metrics: %w[views reach total_interactions],
      days: [ Date.new(2026, 8, 17) ]
    )

    assert_equal 100, account.insights.find_by!(metric_name: "views").value_numeric
    assert_equal 90, account.insights.find_by!(metric_name: "views_organic").value_numeric
    assert_equal 10, account.insights.find_by!(metric_name: "views_paid").value_numeric
    assert_equal 90, account.insights.find_by!(metric_name: "reach_organic").value_numeric
    assert_equal 10, account.insights.find_by!(metric_name: "reach_paid").value_numeric
    assert_equal 90,
      account.insights.find_by!(metric_name: "total_interactions_organic").value_numeric
    assert_equal 10,
      account.insights.find_by!(metric_name: "total_interactions_paid").value_numeric
  end

  test "re-syncing a day updates the row instead of inserting another" do
    days = [ Date.new(2026, 8, 17) ]
    2.times do |run|
      Metrics::MetaAnalyticsSync.new(
        client: TotalValueClient.new,
        now: Time.zone.parse("2026-08-18 02:30:00") + run.hours,
        time_zone: "America/Los_Angeles"
      ).sync_account!(
        platform: "instagram",
        account_key: "build_toronto",
        platform_account_id: "ig-123",
        account_metrics: %w[views],
        days: days
      )
    end

    account = Metrics::MetaAccount.find_by!(platform: "instagram", account_key: "build_toronto")
    assert_equal 1, account.insights.where(metric_name: "views").count
  end

  test "backfill requests one day per date in the range" do
    client = TotalValueClient.new
    sync = Metrics::MetaAnalyticsSync.new(
      client: client,
      now: Time.zone.parse("2026-08-20 02:30:00"),
      time_zone: "America/Los_Angeles"
    )
    account = sync.sync_account!(
      platform: "instagram",
      account_key: "build_toronto",
      platform_account_id: "ig-123",
      account_metrics: %w[views],
      days: []
    )
    account.insights.delete_all

    days = sync.backfill_account_insights!(
      account, metric_names: %w[views], from: Date.new(2026, 8, 1), to: Date.new(2026, 8, 5)
    )

    assert_equal 5, days
    assert_equal 5, account.insights.where(metric_name: "views").count
  end

  test "historical discovery schedules a real baseline at the backfill time" do
    now = Time.zone.parse("2026-08-12 13:00:00")
    sync = Metrics::MetaAnalyticsSync.new(client: FakeClient.new, now: now)
    account = sync.sync_account!(
      platform: "instagram",
      account_key: "build_toronto",
      platform_account_id: "ig-123"
    )

    result = sync.discover_media_page!(account, backfill: true)

    assert_equal 1, result[:processed]
    assert_nil result[:next_cursor]
    assert_equal now, account.media.sole.next_insights_sync_at
  end
end
