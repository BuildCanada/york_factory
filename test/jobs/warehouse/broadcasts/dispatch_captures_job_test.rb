require "test_helper"

class Warehouse::Broadcasts::DispatchCapturesJobTest < ActiveJob::TestCase
  test "dispatches only due enabled streams without a live lease" do
    due = create_state(enabled: true, next_poll_at: 1.minute.ago)
    create_state(enabled: true, next_poll_at: 1.minute.from_now)
    create_state(enabled: false, next_poll_at: 1.minute.ago)

    assert_enqueued_with(job: Warehouse::Broadcasts::CaptureJob, args: [ due.media_stream_id ]) do
      Warehouse::Broadcasts::DispatchCapturesJob.perform_now
    end
    assert_equal 1, enqueued_jobs.count { |job| job.fetch(:job) == Warehouse::Broadcasts::CaptureJob }
  end

  test "does not send on-demand archives through the live capture job" do
    state = create_state(enabled: true, next_poll_at: 1.minute.ago, kind: "on_demand")

    assert_no_enqueued_jobs(only: Warehouse::Broadcasts::CaptureJob) do
      Warehouse::Broadcasts::DispatchCapturesJob.perform_now
    end
    assert state.reload.enabled?
  end

  private

  def create_state(enabled:, next_poll_at:, kind: "event")
    now = Time.current
    stream = Warehouse::MediaStream.create!(
      provider: "cpac", external_id: SecureRandom.uuid, kind:,
      first_seen_at: now, last_seen_at: now
    )
    MediaCaptureState.create!(media_stream: stream, enabled:, next_poll_at:)
  end
end
