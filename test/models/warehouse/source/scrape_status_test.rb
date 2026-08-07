require "test_helper"

class Warehouse::Source::ScrapeStatusTest < ActiveSupport::TestCase
  FakeJob = Data.define(:arguments, :claimed_execution, :failed_execution)

  test "maps queued and running fetch jobs to their sources" do
    jobs = [
      fake_job(source_id: 12),
      fake_job(source_id: 13, claimed: true),
      fake_job(source_id: 14, failed: true)
    ]

    assert_equal({ 12 => "queued", 13 => "running" }, Warehouse::Source::ScrapeStatus.active(jobs:))
  end

  test "running takes precedence when a source has duplicate active jobs" do
    jobs = [ fake_job(source_id: 12), fake_job(source_id: 12, claimed: true) ]

    assert_equal({ 12 => "running" }, Warehouse::Source::ScrapeStatus.active(jobs:))
  end

  private

  def fake_job(source_id:, claimed: false, failed: false)
    FakeJob.new(
      arguments: {
        "arguments" => [
          { "_aj_globalid" => "gid://york-factory/Warehouse::Source::Fetcher/#{source_id}" }
        ]
      },
      claimed_execution: claimed ? Object.new : nil,
      failed_execution: failed ? Object.new : nil
    )
  end
end
