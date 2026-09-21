require "test_helper"

class TestHistoricalCaptureJob < Warehouse::Broadcasts::HistoricalCaptureJob
  cattr_accessor :fake_capturer

  private

  def capturer = self.class.fake_capturer
end

class Warehouse::Broadcasts::HistoricalCaptureJobTest < ActiveJob::TestCase
  setup do
    @stream = create_stream
    @request = BroadcastBackfillRequest.create!(
      scope: "stream", mode: "discover_and_queue", state: "running",
      orchestration_complete: true, started_at: Time.current,
      requested_by: users(:admin)
    )
    @item = @request.items.create!(media_stream: @stream, state: "queued", queued_at: Time.current)
  end

  test "completes capture only at the end of every historical playlist" do
    TestHistoricalCaptureJob.fake_capturer = FakeCapturer.new(captured_count: 4, end_list: true)

    assert_enqueued_with(job: Warehouse::Broadcasts::ProcessJob::BacklogJob, args: [ @stream.id ]) do
      TestHistoricalCaptureJob.perform_now(@stream.id, @item.id)
    end

    assert_equal "completed", @item.reload.state
    assert_equal "completed", @request.reload.state
    state = @stream.reload.media_capture_state
    assert_not state.enabled?
    assert_nil state.lease_token
    assert_nil state.next_poll_at
    assert_equal 100, TestHistoricalCaptureJob.fake_capturer.limit
    assert_equal :historical, TestHistoricalCaptureJob.fake_capturer.source
  end

  test "continues a bounded capture with its durable state" do
    TestHistoricalCaptureJob.fake_capturer = FakeCapturer.new(captured_count: 100, end_list: false)

    TestHistoricalCaptureJob.perform_now(@stream.id, @item.id)

    assert_equal "running", @item.reload.state
    state = @stream.reload.media_capture_state
    assert state.enabled?
    assert_nil state.lease_token
    assert enqueued_jobs.any? { |job| job.fetch(:job) == TestHistoricalCaptureJob && job.fetch(:args) == [ @stream.id, @item.id ] }
    assert enqueued_jobs.any? { |job| job.fetch(:job) == Warehouse::Broadcasts::ProcessJob && job.fetch(:args) == [ @stream.id ] }
  end

  test "a duplicate worker cannot download while the stream lease is owned" do
    state = MediaCaptureState.create!(media_stream: @stream, enabled: true, next_poll_at: Time.current)
    owner = state.claim!(now: Time.current, ttl: 2.minutes)
    TestHistoricalCaptureJob.fake_capturer = NeverCapturer.new

    TestHistoricalCaptureJob.perform_now(@stream.id, @item.id)

    assert_equal 0, TestHistoricalCaptureJob.fake_capturer.calls
    assert_equal owner, state.reload.lease_token
    assert_equal "queued", @item.reload.state
    assert enqueued_jobs.any? { |job| job.fetch(:job) == TestHistoricalCaptureJob && job.fetch(:args) == [ @stream.id, @item.id ] }
  end

  test "rejects a non-CPAC stream without invoking capture" do
    @stream.update!(provider: "other")
    TestHistoricalCaptureJob.fake_capturer = NeverCapturer.new

    TestHistoricalCaptureJob.perform_now(@stream.id, @item.id)

    assert_equal 0, TestHistoricalCaptureJob.fake_capturer.calls
    assert_equal "failed", @item.reload.state
    assert_match(/on-demand CPAC stream/, @item.error)
    assert_nil @stream.reload.media_capture_state
  end

  test "transient transport failure preserves the cursor state and schedules bounded retry" do
    TestHistoricalCaptureJob.fake_capturer = TransientCapturer.new

    assert_enqueued_with(job: TestHistoricalCaptureJob, args: [ @stream.id, @item.id ]) do
      TestHistoricalCaptureJob.perform_now(@stream.id, @item.id)
    end

    state = @stream.reload.media_capture_state
    assert_equal "queued", @item.reload.state
    assert state.enabled?
    assert_nil state.lease_token
    assert_operator state.next_poll_at, :>, Time.current
    assert_equal 1, state.consecutive_failures
    assert_match(/temporary archive failure/, state.last_error)
  end

  test "transient transport failure becomes terminal at the retry bound" do
    MediaCaptureState.create!(
      media_stream: @stream, enabled: true, next_poll_at: Time.current,
      consecutive_failures: Warehouse::Broadcasts::HistoricalCaptureJob::MAX_TRANSIENT_FAILURES - 1
    )
    TestHistoricalCaptureJob.fake_capturer = TransientCapturer.new

    assert_no_enqueued_jobs(only: TestHistoricalCaptureJob) do
      TestHistoricalCaptureJob.perform_now(@stream.id, @item.id)
    end

    state = @stream.reload.media_capture_state
    assert_equal "failed", @item.reload.state
    assert_not state.enabled?
    assert_nil state.next_poll_at
    assert_equal Warehouse::Broadcasts::HistoricalCaptureJob::MAX_TRANSIENT_FAILURES,
      state.consecutive_failures
  end

  private

  def create_stream
    now = Time.current
    Warehouse::MediaStream.create!(
      provider: "cpac", external_id: "#{SecureRandom.uuid}:archive", kind: "on_demand",
      manifest_url: "https://cpac-vod.cdn.vustreams.com/archive/master.m3u8",
      first_seen_at: now, last_seen_at: now
    )
  end

  FakeCapturer = Struct.new(:captured_count, :end_list, :limit, :source, keyword_init: true) do
    def call(limit:, source:, **)
      self.limit = limit
      self.source = source
      Warehouse::Broadcasts::Capturer::Result.new(captured_count:, target_duration: 6, end_list:)
    end
  end

  class NeverCapturer
    attr_reader :calls

    def initialize = @calls = 0

    def call(**)
      @calls += 1
      raise "capture should not run"
    end
  end

  class TransientCapturer
    def call(**)
      raise Warehouse::Broadcasts::HttpClient::TransientError, "temporary archive failure"
    end
  end
end
