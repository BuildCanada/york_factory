require "test_helper"

class Metrics::SyncMetaMediumInsightsJobTest < ActiveJob::TestCase
  class FakeClient
    attr_reader :requests

    def initialize
      @requests = []
    end

    def get(path, params: {})
      @requests << [ path, params ]
      {
        "data" => params.fetch(:metric).split(",").map do |name|
          { "name" => name, "period" => "lifetime", "total_value" => { "value" => 12 } }
        end
      }
    end
  end

  class TestJob < Metrics::SyncMetaMediumInsightsJob
    cattr_accessor :test_client

    private

    def settings_for(_account) = {}.with_indifferent_access
    def client_for(_platform, _settings) = self.class.test_client
  end

  setup do
    @published_at = Time.zone.parse("2026-08-10 12:00:00")
    @scheduled_for = @published_at
    @account = Metrics::MetaAccount.create!(
      platform: "instagram",
      account_key: "build_canada",
      platform_account_id: "ig-account"
    )
    @medium = @account.media.create!(
      platform_media_id: "ig-post",
      published_at: @published_at,
      next_insights_sync_at: @scheduled_for
    )
    TestJob.test_client = FakeClient.new
  end

  teardown do
    TestJob.test_client = nil
  end

  test "stores one idempotent snapshot and advances the post schedule" do
    travel_to(@published_at + 2.hours) do
      TestJob.perform_now(@medium, scheduled_for: @scheduled_for)
    end

    assert_equal 7, @medium.insights.count
    assert_equal [ @scheduled_for ], @medium.insights.distinct.pluck(:observed_at)
    assert_equal @published_at + 1.day, @medium.reload.next_insights_sync_at
    assert_nil @medium.insights_sync_enqueued_at

    TestJob.perform_now(@medium, scheduled_for: @scheduled_for)

    assert_equal 7, @medium.insights.count
    assert_equal 1, TestJob.test_client.requests.count
  end
end
