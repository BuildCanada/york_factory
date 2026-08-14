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

      { "data" => params.fetch(:metric).split(",").map do |name|
        { "name" => name, "period" => "day", "total_value" => { "value" => 42 } }
      end }
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
