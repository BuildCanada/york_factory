require "test_helper"

class Metrics::SyncMetaAnalyticsJobTest < ActiveJob::TestCase
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
      raise account_error if settings[:id] == "broken"
    end

    def account_error
      Metrics::MetaGraphClient::Error.new("failed account")
    end
  end

  class MalformedPayloadTestJob < TestJob
    private

    def account_error
      KeyError.new("media id is missing")
    end
  end

  class PersistenceFailureTestJob < TestJob
    private

    def account_error
      ActiveRecord::RecordNotSaved.new("write failed")
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

  test "isolates malformed payloads and persistence failures by account" do
    [ MalformedPayloadTestJob, PersistenceFailureTestJob ].each do |job_class|
      job = job_class.new

      assert_enqueued_with(job: Metrics::SyncMetaAccountJob) { job.perform_now }
      assert_equal %w[build_canada build_toronto], job.attempted
    end
  end
end
