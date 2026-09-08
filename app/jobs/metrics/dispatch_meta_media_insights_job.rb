class Metrics::DispatchMetaMediaInsightsJob < ApplicationJob
  queue_as :default

  STALE_CLAIM_AFTER = 6.hours
  BATCH_SIZE = 500

  def perform(now: Time.current)
    Metrics::MetaMedium.due_for_insights(now)
      .where(
        "insights_sync_enqueued_at IS NULL OR insights_sync_enqueued_at < ?",
        now - STALE_CLAIM_AFTER
      )
      .order(:next_insights_sync_at)
      .limit(BATCH_SIZE)
      .each do |medium|
        scheduled_for = medium.next_insights_sync_at
        claimed = Metrics::MetaMedium.where(
          id: medium.id,
          next_insights_sync_at: scheduled_for,
          insights_sync_enqueued_at: medium.insights_sync_enqueued_at
        ).update_all(insights_sync_enqueued_at: now)
        next unless claimed == 1

        Metrics::SyncMetaMediumInsightsJob.perform_later(medium, scheduled_for: scheduled_for)
      rescue ActiveJob::EnqueueError
        medium.update_column(:insights_sync_enqueued_at, nil)
        raise
      end
  end
end
