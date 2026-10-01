require "test_helper"

class TestCpacCaptureJob < Warehouse::Broadcasts::CaptureJob
  cattr_accessor :fake_capturer

  private

  def capturer = self.class.fake_capturer
end

class Warehouse::Broadcasts::CaptureJobTest < ActiveJob::TestCase
  setup do
    now = Time.current
    @stream = Warehouse::MediaStream.create!(
      provider: "cpac", external_id: SecureRandom.uuid, kind: "event", provider_state: "live",
      first_seen_at: now, last_seen_at: now
    )
    @state = MediaCaptureState.create!(media_stream: @stream, enabled: true, next_poll_at: now)
  end

  test "processes a captured batch, releases its lease, and schedules the stream id" do
    TestCpacCaptureJob.fake_capturer = FakeCapturer.new(captured_count: 2, end_list: false)

    assert_enqueued_with(job: Warehouse::Broadcasts::ProcessJob, args: [ @stream.id ]) do
      TestCpacCaptureJob.perform_now(@stream.id)
    end

    @state.reload
    assert_nil @state.lease_token
    assert @state.enabled?
    assert @state.next_poll_at.future?
    assert enqueued_jobs.any? { |job| job.fetch(:job) == TestCpacCaptureJob && job.fetch(:args) == [ @stream.id ] }
  end

  test "disables capture after every selected playlist reaches ENDLIST" do
    TestCpacCaptureJob.fake_capturer = FakeCapturer.new(captured_count: 1, end_list: true)

    TestCpacCaptureJob.perform_now(@stream.id)

    assert_not @state.reload.enabled?
    assert_nil @state.next_poll_at
    assert_not enqueued_jobs.any? { |job| job.fetch(:job) == TestCpacCaptureJob }
  end

  test "defers prelive events without invoking transport or recording an error" do
    @stream.update!(provider_state: "prelive", scheduled_start_at: 1.hour.from_now)
    TestCpacCaptureJob.fake_capturer = Object.new.tap do |object|
      def object.call(*) = raise("should not capture")
    end

    TestCpacCaptureJob.perform_now(@stream.id)

    @state.reload
    assert @state.enabled?
    assert_nil @state.last_error
    assert_nil @state.lease_token
    assert @state.next_poll_at > 50.minutes.from_now
  end

  test "closes a previously captured event that disappeared from discovery" do
    @stream.update!(first_seen_at: 1.hour.ago, last_seen_at: 11.minutes.ago)
    @state.update!(last_captured_at: 11.minutes.ago)
    stale_capturer = StaleCapturer.new
    TestCpacCaptureJob.fake_capturer = stale_capturer

    assert_enqueued_with(job: Warehouse::Broadcasts::ProcessJob, args: [ @stream.id ]) do
      TestCpacCaptureJob.perform_now(@stream.id)
    end

    assert stale_capturer.finalized
    assert_not @state.reload.enabled?
    assert_nil @state.lease_token
    assert_nil @state.next_poll_at
  end

  test "retries a live 404 then finalizes after the event disappears" do
    freeze_time do
      @state.update!(last_captured_at: Time.current, next_poll_at: Time.current)
      TestCpacCaptureJob.fake_capturer = ErrorCapturer.new(Warehouse::Broadcasts::HttpClient::NotFoundError)

      TestCpacCaptureJob.perform_now(@stream.id)

      assert @state.reload.enabled?
      assert_nil @state.lease_token
      assert_equal 1, @state.consecutive_failures
      assert_enqueued_with(job: TestCpacCaptureJob, args: [ @stream.id ], at: 2.seconds.from_now)
      assert_enqueued_with(job: Warehouse::Broadcasts::ProcessJob, args: [ @stream.id ])

      travel 11.minutes
      stale_capturer = StaleCapturer.new
      TestCpacCaptureJob.fake_capturer = stale_capturer
      TestCpacCaptureJob.perform_now(@stream.id)

      assert stale_capturer.finalized
      assert_not @state.reload.enabled?
      assert_nil @state.last_error
      assert_nil @state.next_poll_at
    end
  end

  test "continuous channels recover after repeated missing segments beyond the old retry limit" do
    @stream.update!(kind: "continuous")
    @state.update!(consecutive_failures: 100, cursor: { "tracks" => { "video" => { "last_sequence" => 12 } } })
    TestCpacCaptureJob.fake_capturer = ErrorCapturer.new(Warehouse::Broadcasts::HttpClient::NotFoundError)

    freeze_time do
      @state.update!(next_poll_at: Time.current)
      TestCpacCaptureJob.perform_now(@stream.id)
      assert @state.reload.enabled?
      assert_equal 101, @state.consecutive_failures
      assert_equal 5.minutes.from_now, @state.next_poll_at
      assert_equal 12, @state.cursor.dig("tracks", "video", "last_sequence")
      assert_enqueued_with(job: TestCpacCaptureJob, args: [ @stream.id ], at: 5.minutes.from_now)

      travel 5.minutes
      TestCpacCaptureJob.fake_capturer = FakeCapturer.new(captured_count: 1, end_list: false)
      TestCpacCaptureJob.perform_now(@stream.id)
      assert @state.reload.enabled?
      assert_equal 0, @state.consecutive_failures
      assert_nil @state.last_error
      assert_nil @state.lease_token
    end
  end

  test "DNS and server failures keep live polling enabled" do
    TestCpacCaptureJob.fake_capturer = ErrorCapturer.new(Warehouse::Broadcasts::HttpClient::TransientError)

    assert_enqueued_with(job: TestCpacCaptureJob, args: [ @stream.id ]) do
      TestCpacCaptureJob.perform_now(@stream.id)
    end
    assert @state.reload.enabled?
    assert @state.next_poll_at.future?
    assert_nil @state.lease_token
    assert_match(/temporary failure/, @state.last_error)
  end

  test "expires disappeared events even if no bytes were captured" do
    @stream.update!(first_seen_at: 1.hour.ago, last_seen_at: 11.minutes.ago)
    TestCpacCaptureJob.fake_capturer = StaleCapturer.new

    TestCpacCaptureJob.perform_now(@stream.id)

    assert TestCpacCaptureJob.fake_capturer.finalized
    assert_not @state.reload.enabled?
    assert_nil @state.last_error
  end

  test "an event still in discovery stays enabled after a missing playlist" do
    @state.update!(last_captured_at: 1.hour.ago)
    TestCpacCaptureJob.fake_capturer = ErrorCapturer.new(Warehouse::Broadcasts::HttpClient::NotFoundError)

    TestCpacCaptureJob.perform_now(@stream.id)

    assert @state.reload.enabled?
    assert @state.next_poll_at.future?
  end

  test "permanent policy failures disable capture without retry" do
    TestCpacCaptureJob.fake_capturer = ErrorCapturer.new(Warehouse::Broadcasts::HttpClient::PermanentError)

    assert_no_enqueued_jobs do
      TestCpacCaptureJob.perform_now(@stream.id)
    end
    assert_not @state.reload.enabled?
    assert_nil @state.next_poll_at
    assert_nil @state.lease_token
  end

  test "operator paused streams are not restarted" do
    @state.update!(enabled: false)
    TestCpacCaptureJob.fake_capturer = ErrorCapturer.new(Warehouse::Broadcasts::HttpClient::NotFoundError)

    assert_no_enqueued_jobs do
      TestCpacCaptureJob.perform_now(@stream.id)
    end
    assert_not @state.reload.enabled?
    assert_nil @state.last_error
  end

  ErrorCapturer = Struct.new(:error_class) do
    def call(**)
      raise error_class, "temporary failure"
    end
  end

  FakeCapturer = Struct.new(:captured_count, :end_list, keyword_init: true) do
    def call(**)
      yield "captured-object"
      Warehouse::Broadcasts::Capturer::Result.new(captured_count:, target_duration: 6, end_list:)
    end
  end

  class StaleCapturer
    attr_reader :finalized

    def finalize_stale!(**)
      @finalized = true
    end
  end
end
