class Metrics::DispatchSubstackPostDetailsJob < Metrics::SubstackJob
  STALE_CLAIM_AFTER = 6.hours
  BATCH_SIZE = 100

  def perform(now: Time.current)
    Metrics::SubstackPost.due_for_details(now)
      .where(
        "details_sync_enqueued_at IS NULL OR details_sync_enqueued_at < ?",
        now - STALE_CLAIM_AFTER
      )
      .order(:next_details_sync_at)
      .limit(BATCH_SIZE)
      .each do |post|
        next if settings_for(post.publication)[:cookies].blank?

        enqueue(post, now: now)
      end
  end

  private

  def enqueue(post, now:)
    scheduled_for = post.next_details_sync_at
    claimed = Metrics::SubstackPost.where(
      id: post.id,
      next_details_sync_at: scheduled_for,
      details_sync_enqueued_at: post.details_sync_enqueued_at
    ).update_all(details_sync_enqueued_at: now)
    return unless claimed == 1

    Metrics::SyncSubstackPostDetailsJob.perform_later(post, scheduled_for: scheduled_for)
  rescue ActiveJob::EnqueueError
    post.update_column(:details_sync_enqueued_at, nil)
    raise
  end
end
