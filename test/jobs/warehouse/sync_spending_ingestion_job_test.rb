require "test_helper"
require "active_job/continuation/test_helper"

class TestSyncSpendingIngestionJob < Warehouse::SyncSpendingIngestionJob
  cattr_accessor :synced_ids, default: []

  private

  def sync(award)
    self.class.synced_ids << award.id
    award.update_column(:search_synced_at, Time.current)
  end
end

class Warehouse::SyncSpendingIngestionJobTest < ActiveJob::TestCase
  include ActiveJob::Continuation::TestHelper

  setup do
    @source = Warehouse::Source.create!(
      name: "spending_sync_job_test_#{SecureRandom.hex(4)}",
      url: "https://example.test/awards.csv",
      format: "csv"
    )
    @ingestion = @source.raw_ingestions.create!(
      fetched_at: Time.current,
      raw_file_path: "raw/test/awards.csv",
      checksum: SecureRandom.hex(16),
      status: :complete
    )
    @awards = 3.times.map { |index| create_award(index) }
    TestSyncSpendingIngestionJob.synced_ids = []
  end

  test "syncs one ingestion without creating per-record jobs" do
    assert_no_enqueued_jobs only: Search::SyncJob do
      TestSyncSpendingIngestionJob.perform_now(@ingestion)
    end

    assert @awards.all? { |award| award.reload.search_synced_at.present? }
    assert_equal @awards.map(&:id), TestSyncSpendingIngestionJob.synced_ids
  end

  test "resumes at the first unsynced award after interruption" do
    TestSyncSpendingIngestionJob.perform_later(@ingestion)

    interrupt_job_during_step(
      TestSyncSpendingIngestionJob,
      :sync_awards,
      cursor: @awards.first.id.succ
    ) { perform_enqueued_jobs }

    assert_predicate @awards.first.reload, :search_synced_at?
    assert_nil @awards.second.reload.search_synced_at
    assert_nil @awards.third.reload.search_synced_at

    perform_enqueued_jobs

    assert @awards.all? { |award| award.reload.search_synced_at.present? }
    assert_equal @awards.map(&:id), TestSyncSpendingIngestionJob.synced_ids
  end

  private

  def create_award(index)
    now = Time.current
    @source.spending_awards.create!(
      raw_ingestion: @ingestion,
      external_key: "award-#{index}",
      award_type: "grant",
      title: "Award #{index}",
      description: "Supports useful work",
      recipient_name: "Recipient #{index}",
      fiscal_year: 2025,
      amount: 1_000 + index,
      first_seen_at: now,
      last_seen_at: now
    )
  end
end
