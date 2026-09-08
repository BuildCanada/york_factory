require "test_helper"

class Metrics::BackfillSubstackPostsJobTest < ActiveJob::TestCase
  class FakeClient
    attr_reader :offsets

    def initialize
      @offsets = []
    end

    def get(path, params: {})
      raise "Unexpected path: #{path}" unless path == "/api/v1/archive"

      @offsets << params.fetch(:offset)
      count = params[:offset].zero? ? 15 : 1
      count.times.map do |index|
        number = params[:offset] + index
        {
          "id" => number + 1,
          "slug" => "post-#{number + 1}",
          "title" => "Post #{number + 1}",
          "post_date" => "2025-01-01T12:00:00.000Z",
          "is_published" => true
        }
      end
    end
  end

  class TestJob < Metrics::BackfillSubstackPostsJob
    cattr_accessor :test_client

    private

    def substack_config = { configured: true }.with_indifferent_access

    def configured_accounts
      [ [ "build_canada", { url: "https://buildcanada.substack.com" }.with_indifferent_access ] ]
    end

    def client_for(_settings) = self.class.test_client
  end

  setup do
    @publication = Metrics::SubstackPublication.create!(
      account_key: "build_canada",
      publication_id: "publication-1",
      url: "https://buildcanada.substack.com"
    )
    TestJob.test_client = FakeClient.new
  end

  teardown do
    TestJob.test_client = nil
  end

  test "checkpoints offset pagination and marks the publication backfilled" do
    now = Time.zone.parse("2026-08-12 13:00:00")

    travel_to(now) { TestJob.perform_now }

    assert_equal 16, @publication.posts.count
    assert_equal [ 0, 15 ], TestJob.test_client.offsets
    assert_equal [ now ], @publication.posts.distinct.pluck(:next_details_sync_at)
    assert_equal now, @publication.reload.posts_backfilled_at
  end
end
