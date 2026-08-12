require "test_helper"
require "active_job/continuation/test_helper"

class TestSyncSubstackSubscribersJob < SyncSubstackSubscribersJob
  cattr_accessor :batches, default: []
  cattr_accessor :fail_import, default: false

  private

  def configured?
    true
  end

  def batch_size
    2
  end

  def importer
    job_class = self.class
    Object.new.tap do |fake|
      fake.define_singleton_method(:import!) do |subscribers|
        raise Metrics::SubstackClient::Error, "import failed" if job_class.fail_import

        job_class.batches << subscribers.map(&:email)
        99_001
      end
    end
  end
end

class SyncSubstackSubscribersJobTest < ActiveJob::TestCase
  include ActiveJob::Continuation::TestHelper

  setup do
    subscribers(:existing_subscriber).update_columns(substack_synced_at: Time.current)
    TestSyncSubstackSubscribersJob.batches = []
    TestSyncSubstackSubscribersJob.fail_import = false
  end

  test "imports every unsynced subscriber in batches and marks accepted records" do
    subscribers = 3.times.map do |index|
      Subscriber.create!(email: "person#{index}@example.com")
    end

    TestSyncSubstackSubscribersJob.perform_now

    assert_equal subscribers.map(&:email).each_slice(2).to_a, TestSyncSubstackSubscribersJob.batches
    subscribers.each do |subscriber|
      assert_predicate subscriber.reload, :substack_synced_at?
      assert_equal 99_001, subscriber.substack_import_id
    end
  end

  test "domain-limited test run only imports matching addresses" do
    matching = Subscriber.create!(email: "team@buildcanada.com")
    other = Subscriber.create!(email: "reader@example.com")

    TestSyncSubstackSubscribersJob.perform_now(email_domain: "buildcanada.com")

    assert_equal [ [ matching.email ] ], TestSyncSubstackSubscribersJob.batches
    assert_predicate matching.reload, :substack_synced_at?
    assert_nil other.reload.substack_synced_at
  end

  test "does not mark subscribers when Substack rejects the import" do
    subscriber = Subscriber.create!(email: "team@buildcanada.com")
    TestSyncSubstackSubscribersJob.fail_import = true

    assert_enqueued_with(job: TestSyncSubstackSubscribersJob) do
      TestSyncSubstackSubscribersJob.perform_now(email_domain: "buildcanada.com")
    end

    assert_nil subscriber.reload.substack_synced_at
  end
end
