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
