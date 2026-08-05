module Search
  class DeliverDigestJob < ApplicationJob
    retry_on StandardError, wait: :polynomially_longer, attempts: 10

    def perform(batch_id)
      batch = NotificationBatch.find_by(id: batch_id)
      return unless batch&.mode == "digest"

      if batch.state == "open" && batch.scheduled_for&.future?
        self.class.set(wait_until: batch.scheduled_for).perform_later(batch.id)
        return
      end

      batch.with_lock do
        if batch.state == "open"
          return unless batch.saved_search_matches.exists?

          batch.close!
          batch.saved_search_matches.update_all(state: "dispatching", updated_at: Time.current)
        end
      end

      batch.notification_deliveries.where(status: %w[pending failed]).find_each do |delivery|
        Search::DeliverNotificationJob.perform_later(delivery.id)
      end
    end
  end
end
