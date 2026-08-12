require "test_helper"

class Metrics::BackfillMetaMediaJobTest < ActiveJob::TestCase
  class FakeClient
    attr_reader :requests

    def initialize
      @requests = []
    end

    def get(path, params: {})
      @requests << [ path, params ]
      id = params[:after] ? "older-post" : "newer-post"
      response = {
        "data" => [ {
          "id" => id,
          "caption" => id,
          "media_type" => "IMAGE",
          "permalink" => "https://www.instagram.com/p/#{id}/",
          "timestamp" => "2025-01-01T12:00:00+0000"
        } ]
      }
      unless params[:after]
        response["paging"] = {
          "next" => "https://graph.facebook.com/next-page",
          "cursors" => { "after" => "cursor-1" }
        }
      end
      response
    end
  end

  class TestJob < Metrics::BackfillMetaMediaJob
    cattr_accessor :test_client

    private

    def meta_config = { access_token: "test-token" }.with_indifferent_access

    def configured_accounts
      [ [ "instagram", "build_canada", { id: "ig-account" }.with_indifferent_access ] ]
    end

    def client_for(_platform, _settings) = self.class.test_client
  end

  setup do
    @account = Metrics::MetaAccount.create!(
      platform: "instagram",
      account_key: "build_canada",
      platform_account_id: "ig-account"
    )
    TestJob.test_client = FakeClient.new
  end

  teardown do
    TestJob.test_client = nil
  end

  test "checkpoints each page and marks the account backfilled" do
    now = Time.zone.parse("2026-08-12 13:00:00")

    travel_to(now) { TestJob.perform_now }

    assert_equal %w[newer-post older-post], @account.media.order(:id).pluck(:platform_media_id)
    assert_equal [ now ], @account.media.distinct.pluck(:next_insights_sync_at)
    assert_equal now, @account.reload.media_backfilled_at
    assert_equal [ nil, "cursor-1" ], TestJob.test_client.requests.map { |_path, params| params[:after] }
  end
end
