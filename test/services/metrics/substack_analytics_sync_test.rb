require "test_helper"

class Metrics::SubstackAnalyticsSyncTest < ActiveSupport::TestCase
  class FakeClient
    attr_reader :requests

    def initialize
      @requests = []
    end

    def get(path, params: {})
      @requests << [ path, params ]
      case path
      when "/api/v1/publication"
        { "id" => 4_062_955, "name" => "Build Canada", "hero_text" => "Build more." }
      when "/api/v1/archive"
        [ archive_post ]
      when "/api/v1/post_management/detail/167992765"
        { "posts" => [ details ] }
      else
        raise "Unexpected request: #{path}"
      end
    end

    private

    def archive_post
      {
        "id" => 167_992_765,
        "publication_id" => 4_062_955,
        "slug" => "build-everything",
        "title" => "Build Everything",
        "subtitle" => "Canada needs abundance",
        "canonical_url" => "https://buildcanada.substack.com/p/build-everything",
        "audience" => "everyone",
        "type" => "newsletter",
        "cover_image" => "https://cdn.substack.com/cover.jpg",
        "post_date" => "2026-08-10T12:00:00.000Z",
        "is_published" => true
      }
    end

    def details
      {
        "id" => 167_992_765,
        "title" => "Build Everything",
        "stats" => {
          "views" => 4_900,
          "opens" => 3_200,
          "open_rate" => 0.65,
          "clicks" => 280,
          "click_through_rate" => 0.0875,
          "signups" => 9,
          "subscribes" => 2,
          "referrers" => { "google" => 90 },
          "firstWeekDailyStats" => [
            {
              "dt" => "2026-08-10T00:00:00.000Z",
              "day_n" => 0,
              "views" => 3_900,
              "cumulative_views" => 3_900,
              "signups" => 7
            },
            {
              "dt" => "2026-08-11T00:00:00.000Z",
              "day_n" => 1,
              "views" => 1_000,
              "cumulative_views" => 4_900,
              "signups" => 2
            }
          ]
        }
      }
    end
  end

  class LiveArchiveShapeClient < FakeClient
    def get(path, params: {})
      payload = super
      return payload unless path == "/api/v1/archive"

      payload.map { |post| post.except("is_published") }
    end
  end

  class TrafficClient
    attr_reader :requests

    def initialize(granularity: :daily)
      @granularity = granularity
      @requests = []
    end

    def get(path, params: {})
      raise "Unexpected request: #{path}" unless path.include?("publication_traffic/timeseries")

      @requests << params
      from = Date.iso8601(params.fetch(:from)) + 1
      to = Date.iso8601(params.fetch(:to))
      step = @granularity == :daily ? 1 : 7
      dates = []
      date = from
      while date <= to
        dates << date
        date += step
      end
      dates.map.with_index { |day, index| [ day.strftime("%Y/%m/%d"), index + 100 ] }
    end
  end

  test "syncs publication, archive post, details, and all stat payloads idempotently" do
    now = Time.zone.parse("2026-08-12 13:00:00")
    canonical_url = "https://buildcanada.substack.com/p/build-everything"
    feed_post = ::SubstackPost.create!(
      external_url: canonical_url,
      title: "Build Everything",
      posted_at: now - 2.days
    )
    client = FakeClient.new
    sync = Metrics::SubstackAnalyticsSync.new(client: client, now: now)

    publication = sync.sync_publication!(
      account_key: "build_canada",
      url: "https://buildcanada.substack.com"
    )
    sync.discover_recent_posts!(publication)
    post = publication.posts.sole

    assert_equal "4062955", publication.publication_id
    assert_equal "Build Canada", publication.name
    assert_equal "167992765", post.substack_post_id
    assert_equal feed_post, post.feed_post
    assert_equal Time.zone.parse("2026-08-10 12:00:00"), post.next_details_sync_at
    assert_equal "newsletter", post.post_type

    sync.sync_post_details!(post, scheduled_for: now)
    sync.sync_post_details!(post, scheduled_for: now)

    assert_equal 3, post.metric_snapshots.count
    current = post.metric_snapshots.find_by!(snapshot_type: "current")
    assert_equal 4_900, current.views
    assert_equal 0.65, current.open_rate
    assert_equal({ "google" => 90 }, current.stats_payload["referrers"])
    daily = post.metric_snapshots.where(snapshot_type: "first_week_daily").order(:day_number)
    assert_equal [ 0, 1 ], daily.pluck(:day_number)
    assert_equal [ 3_900, 4_900 ], daily.pluck(:cumulative_views)
    assert_equal 167_992_765, post.details_payload["id"]
  end

  test "backfill schedules a current baseline rather than a historical fake" do
    now = Time.zone.parse("2026-08-12 13:00:00")
    sync = Metrics::SubstackAnalyticsSync.new(client: FakeClient.new, now: now)
    publication = sync.sync_publication!(
      account_key: "build_canada",
      url: "https://buildcanada.substack.com"
    )

    result = sync.discover_posts_page!(publication, offset: 0, backfill: true)

    assert_equal 1, result[:processed]
    assert_nil result[:next_offset]
    assert_equal now, publication.posts.sole.next_details_sync_at
  end

  test "treats an archive post with a publication date as published" do
    sync = Metrics::SubstackAnalyticsSync.new(client: LiveArchiveShapeClient.new)
    publication = sync.sync_publication!(
      account_key: "build_canada",
      url: "https://buildcanada.substack.com"
    )

    sync.discover_recent_posts!(publication)

    assert publication.posts.sole.published?
  end

  test "syncs long publication traffic ranges through daily 90-day windows" do
    now = Time.zone.parse("2026-08-12 13:00:00")
    publication = Metrics::SubstackPublication.create!(
      account_key: "build_canada",
      publication_id: "publication-1",
      url: "https://buildcanada.substack.com"
    )
    client = TrafficClient.new
    sync = Metrics::SubstackAnalyticsSync.new(client: client, now: now)

    count = sync.sync_publication_traffic!(
      publication,
      start_date: Date.new(2026, 2, 13),
      end_date: Date.new(2026, 8, 12)
    )

    assert_equal 181, count
    assert_equal 3, client.requests.size
    assert_equal 90, Date.iso8601(client.requests.first[:to]) -
      Date.iso8601(client.requests.first[:from])
    stats = Metrics::SubstackStat.for_account("build_canada")
    assert_equal 181, stats.count
    assert_equal Date.new(2026, 2, 13), stats.minimum(:date)
    assert_equal Date.new(2026, 8, 12), stats.maximum(:date)
    assert_equal [ "substack_api" ], stats.distinct.pluck(:source)
    assert_equal now, stats.order(:date).first.scraped_at
  end

  test "rejects weekly traffic responses without storing them as daily" do
    publication = Metrics::SubstackPublication.create!(
      account_key: "build_canada",
      publication_id: "publication-1",
      url: "https://buildcanada.substack.com"
    )
    sync = Metrics::SubstackAnalyticsSync.new(client: TrafficClient.new(granularity: :weekly))

    assert_no_difference -> { Metrics::SubstackStat.count } do
      error = assert_raises(Metrics::SubstackClient::Error) do
        sync.sync_publication_traffic!(
          publication,
          start_date: Date.new(2026, 5, 14),
          end_date: Date.new(2026, 8, 12)
        )
      end
      assert_match "was not daily", error.message
    end
  end
end
