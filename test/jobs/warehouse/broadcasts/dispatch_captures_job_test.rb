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

  test "recovers transport-disabled events and channels but leaves pauses and permanent failures alone" do
    recoverable = create_state(enabled: false, next_poll_at: nil)
    recoverable.update!(last_error: "Warehouse::Broadcasts::HttpClient::PermanentError: HTTP 404 for https://cpac.example/live.m3u8")
    dns = create_state(enabled: false, next_poll_at: nil, kind: "continuous")
    dns.update!(last_error: "Warehouse::Broadcasts::HttpClient::PermanentError: host did not resolve")
    paused = create_state(enabled: false, next_poll_at: nil)
    forbidden = create_state(enabled: false, next_poll_at: nil)
    forbidden.update!(last_error: "Warehouse::Broadcasts::HttpClient::PermanentError: HTTP 403 for https://cpac.example/live.m3u8")
    historical = create_state(enabled: false, next_poll_at: nil, kind: "on_demand")
    historical.update!(last_error: recoverable.last_error)
    leased = create_state(enabled: false, next_poll_at: nil)
    leased.update!(last_error: recoverable.last_error, lease_token: "active-owner", lease_expires_at: 2.minutes.from_now)

    Warehouse::Broadcasts::DispatchCapturesJob.perform_now

    assert recoverable.reload.enabled?
    assert dns.reload.enabled?
    assert_not paused.reload.enabled?
    assert_not forbidden.reload.enabled?
    assert_not historical.reload.enabled?
    assert_not leased.reload.enabled?
    assert_equal [ recoverable.media_stream_id, dns.media_stream_id ].sort,
      enqueued_jobs.select { |job| job[:job] == Warehouse::Broadcasts::CaptureJob }.map { |job| job[:args].first }.sort
  end

  test "a recovered disabled stale event closes its recording and queues tail processing" do
    state = create_state(enabled: false, next_poll_at: nil)
    stream = state.media_stream
    stream.update!(first_seen_at: 1.hour.ago, last_seen_at: 11.minutes.ago)
    state.update!(last_captured_at: 11.minutes.ago,
      last_error: "Warehouse::Broadcasts::HttpClient::PermanentError: HTTP 404 for https://cpac.example/live.m3u8")
    recording = stream.recordings.create!(recording_key: "stuck", starts_at: 1.hour.ago, state: "open")
    object = stream.objects.create!(kind: "source_segment", identity_key: "last-source", object_key: "last-source",
      checksum: "checksum", byte_size: 100, content_type: "video/mp2t", starts_at: 12.minutes.ago, ends_at: 11.minutes.ago)
    capturer = Warehouse::Broadcasts::Capturer.new(storage: Object.new)
    Warehouse::Broadcasts::Capturer.stub(:new, ->(*) { capturer }) do
      perform_enqueued_jobs(only: Warehouse::Broadcasts::CaptureJob) do
        Warehouse::Broadcasts::DispatchCapturesJob.perform_now
      end
    end

    assert_equal "partial", recording.reload.state
    assert_equal object.reload.ends_at, recording.ends_at
    assert recording.metadata.fetch("capture_complete")
    assert_not state.reload.enabled?
    assert_nil state.last_error
    assert_enqueued_with(job: Warehouse::Broadcasts::ProcessJob, args: [ stream.id ])
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
