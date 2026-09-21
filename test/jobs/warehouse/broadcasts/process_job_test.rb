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

  [
    Aws::S3::Errors::ServiceError.new(nil, "temporary storage outage"),
    Seahorse::Client::NetworkingError.new(IOError.new("connection reset")),
    Warehouse::Broadcasts::Command::Failed.new("ffmpeg failed", argv: [ "ffmpeg" ]),
    Warehouse::Broadcasts::Command::TimedOut.new("ffprobe timed out", argv: [ "ffprobe" ]),
    Warehouse::Broadcasts::Processor::InvalidOutput.new("ffprobe returned invalid timing"),
    ActiveStorage::FileNotFoundError.new
  ].each do |failure|
    test "retries #{failure.class} after capture has finalized" do
      now = Time.current
      stream = Warehouse::MediaStream.create!(provider: "cpac", external_id: SecureRandom.uuid,
        kind: "event", first_seen_at: now, last_seen_at: now)
      stream.recordings.create!(recording_key: "final", starts_at: now - 60, ends_at: now, state: "finalized")
      state = MediaCaptureState.create!(media_stream: stream, enabled: false)
      calls = 0
      processor = Object.new
      processor.define_singleton_method(:call) do
        calls += 1
        raise failure if calls == 1
        1
      end
      processor.define_singleton_method(:more_work?) { true }

      Warehouse::Broadcasts::Processor.stub(:new, ->(*) { processor }) do
        assert_enqueued_with(job: Warehouse::Broadcasts::ProcessJob, args: [ stream.id ]) do
          Warehouse::Broadcasts::ProcessJob.perform_now(stream.id)
        end
        assert_no_enqueued_jobs(only: Warehouse::Broadcasts::ProcessJob::BacklogJob)
        assert_enqueued_with(job: Warehouse::Broadcasts::ProcessJob::BacklogJob, args: [ stream.id ]) do
          perform_enqueued_jobs(only: Warehouse::Broadcasts::ProcessJob)
        end
      end
      assert_equal 2, calls
      assert_not state.reload.enabled?
    end
  end

  test "persistent processing errors exhaust bounded retries and remain visible" do
    stream = Warehouse::MediaStream.create!(provider: "cpac", external_id: SecureRandom.uuid,
      kind: "event", first_seen_at: Time.current, last_seen_at: Time.current)
    calls = 0
    processor = Object.new
    processor.define_singleton_method(:call) do
      calls += 1
      raise Warehouse::Broadcasts::Processor::InvalidOutput, "invalid media"
    end

    Warehouse::Broadcasts::Processor.stub(:new, ->(*) { processor }) do
      Warehouse::Broadcasts::ProcessJob.perform_now(stream.id)
      2.times { ActiveJob::Base.execute(enqueued_jobs.shift) }
      assert_raises(Warehouse::Broadcasts::Processor::InvalidOutput) do
        ActiveJob::Base.execute(enqueued_jobs.shift)
      end
    end
    assert_equal 4, calls
    assert_no_enqueued_jobs(only: Warehouse::Broadcasts::ProcessJob::BacklogJob)
  end

  test "concurrency key coalesces jobs for the same stream" do
    job = Warehouse::Broadcasts::ProcessJob
    assert_equal 1, job.concurrency_limit
    assert_equal :discard, job.concurrency_on_conflict
    assert_equal "broadcast-process-42", job.concurrency_key.call(42)
  end
end
