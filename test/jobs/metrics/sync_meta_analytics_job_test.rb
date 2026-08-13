require "test_helper"

class Metrics::SyncMetaAnalyticsJobTest < ActiveJob::TestCase
  class FailingRetryJob
    def self.perform_later(*)
      raise ActiveJob::EnqueueError, "queue unavailable"
    end
  end

  class TestJob < Metrics::SyncMetaAnalyticsJob
    attr_reader :attempted

    private

    def meta_config
      { access_token: "token" }.with_indifferent_access
    end

    def configured_accounts
      [
        [ "instagram", "build_canada", { id: "broken" }.with_indifferent_access ],
        [ "instagram", "build_toronto", { id: "healthy" }.with_indifferent_access ]
      ]
    end

    def sync_account(platform, account_key, settings)
      @attempted ||= []
      @attempted << account_key
      raise Metrics::MetaGraphClient::Error, "failed account" if settings[:id] == "broken"
    end
  end

  class QueueFailureTestJob < TestJob
    private

    def retry_job_class
      FailingRetryJob
    end
  end

  test "isolates failed accounts and continues syncing later accounts" do
    job = TestJob.new

    assert_enqueued_with(
      job: Metrics::SyncMetaAccountJob,
      args: [ "instagram", "build_canada", { "id" => "broken" } ]
    ) do
      job.perform_now
    end

    assert_equal %w[build_canada build_toronto], job.attempted
  end

  test "continues syncing when enqueueing an account retry fails" do
    job = QueueFailureTestJob.new

    assert_nothing_raised { job.perform_now }

    assert_equal %w[build_canada build_toronto], job.attempted
  end
end
