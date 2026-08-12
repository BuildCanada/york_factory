require "test_helper"

class Metrics::SyncSubstackPostDetailsJobTest < ActiveJob::TestCase
  class FakeClient
    attr_reader :requests

    def initialize
      @requests = []
    end

    def get(path, params: {})
      @requests << [ path, params ]
      {
        "posts" => [ {
          "id" => 1,
          "stats" => {
            "views" => 250,
            "firstWeekDailyStats" => []
          }
        } ]
      }
    end
  end

  class TestJob < Metrics::SyncSubstackPostDetailsJob
    cattr_accessor :test_client

    private

    def settings_for(_publication)
      {
        url: "https://buildcanada.substack.com",
        cookies: { "substack.sid" => "test" }
      }.with_indifferent_access
    end

    def client_for(_settings) = self.class.test_client
  end

  setup do
    @published_at = Time.zone.parse("2026-08-10 12:00:00")
    publication = Metrics::SubstackPublication.create!(
      account_key: "build_canada",
      publication_id: "publication-1",
      url: "https://buildcanada.substack.com"
    )
    @post = publication.posts.create!(
      substack_post_id: "post-1",
      published_at: @published_at,
      published: true,
      next_details_sync_at: @published_at
    )
    TestJob.test_client = FakeClient.new
  end

  teardown do
    TestJob.test_client = nil
  end

  test "syncs an idempotent snapshot and advances the cadence" do
    travel_to(@published_at + 2.hours) do
      TestJob.perform_now(@post, scheduled_for: @published_at)
    end

    snapshot = @post.metric_snapshots.sole
    assert_equal 250, snapshot.views
    assert_equal @published_at, snapshot.observed_at
    assert_equal @published_at + 1.day, @post.reload.next_details_sync_at

    TestJob.perform_now(@post, scheduled_for: @published_at)

    assert_equal 1, @post.metric_snapshots.count
    assert_equal 1, TestJob.test_client.requests.count
  end
end
