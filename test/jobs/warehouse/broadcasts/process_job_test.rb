require "test_helper"

class Warehouse::Broadcasts::ProcessJobTest < ActiveJob::TestCase
  test "runs one bounded processor batch and schedules remaining work indirectly" do
    stream = Warehouse::MediaStream.create!(
      provider: "cpac", external_id: "job-#{SecureRandom.hex(4)}", kind: "event",
      first_seen_at: Time.current, last_seen_at: Time.current
    )
    processor = Object.new
    processor.define_singleton_method(:call) { 4 }
    processor.define_singleton_method(:more_work?) { true }

    Warehouse::Broadcasts::Processor.stub(:new, ->(*) { processor }) do
      assert_enqueued_with(job: Warehouse::Broadcasts::ProcessJob::BacklogJob) do
        Warehouse::Broadcasts::ProcessJob.perform_now(stream.id)
      end
    end
  end

  test "concurrency key coalesces jobs for the same stream" do
    job = Warehouse::Broadcasts::ProcessJob
    assert_equal 1, job.concurrency_limit
    assert_equal :discard, job.concurrency_on_conflict
    assert_equal "broadcast-process-42", job.concurrency_key.call(42)
  end
end
