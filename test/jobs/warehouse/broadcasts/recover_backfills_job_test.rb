require "test_helper"

class Warehouse::Broadcasts::RecoverBackfillsJobTest < ActiveJob::TestCase
  test "recovers one stale queued capture and advances its recovery timestamp" do
    item = create_item(state: "queued", updated_at: 10.minutes.ago)
    previous_update = item.updated_at

    assert_enqueued_with(job: Warehouse::Broadcasts::HistoricalCaptureJob, args: [ item.media_stream_id, item.id ]) do
      Warehouse::Broadcasts::RecoverBackfillsJob.perform_now
    end

    assert_operator item.reload.updated_at, :>, previous_update
    recovered = enqueued_jobs.find { |job| job.fetch(:job) == Warehouse::Broadcasts::HistoricalCaptureJob }
    assert_equal "default", recovered.fetch(:queue)
  end

  test "does not duplicate an active capture lease" do
    item = create_item(state: "running", updated_at: 10.minutes.ago)
    state = MediaCaptureState.create!(media_stream: item.media_stream, enabled: true, next_poll_at: Time.current)
    state.claim!(now: Time.current, ttl: 2.minutes)

    assert_no_enqueued_jobs(only: Warehouse::Broadcasts::HistoricalCaptureJob) do
      Warehouse::Broadcasts::RecoverBackfillsJob.perform_now
    end
  end

  test "does not bypass a transient failure backoff" do
    item = create_item(state: "queued", updated_at: Time.current)
    MediaCaptureState.create!(
      media_stream: item.media_stream, enabled: true,
      next_poll_at: 5.minutes.from_now, consecutive_failures: 1,
      last_error: "temporary archive failure"
    )

    assert_no_enqueued_jobs(only: Warehouse::Broadcasts::HistoricalCaptureJob) do
      Warehouse::Broadcasts::RecoverBackfillsJob.perform_now
    end
  end

  test "recovers an expired request lease on the default queue" do
    request = BroadcastBackfillRequest.create!(
      scope: "date_range", mode: "discover_only", starts_on: Date.current,
      ends_on: Date.current, state: "running", requested_by: users(:admin),
      lease_token: SecureRandom.uuid, lease_expires_at: 1.minute.ago
    )

    assert_enqueued_with(job: Warehouse::Broadcasts::BackfillJob) do
      Warehouse::Broadcasts::RecoverBackfillsJob.perform_now
    end

    request.reload
    assert request.lease_token.present?
    assert_predicate request.lease_expires_at, :future?
    recovered = enqueued_jobs.find { |job| job.fetch(:job) == Warehouse::Broadcasts::BackfillJob }
    assert_equal "default", recovered.fetch(:queue)
  end

  private

  def create_item(state:, updated_at:)
    now = Time.current
    stream = Warehouse::MediaStream.create!(
      provider: "cpac", external_id: "#{SecureRandom.uuid}:archive", kind: "on_demand",
      first_seen_at: now, last_seen_at: now
    )
    request = BroadcastBackfillRequest.create!(
      scope: "stream", mode: "discover_and_queue", state: "running",
      orchestration_complete: true, started_at: now, requested_by: users(:admin)
    )
    item = request.items.create!(media_stream: stream, state:, queued_at: now)
    item.update_column(:updated_at, updated_at)
    item
  end
end
