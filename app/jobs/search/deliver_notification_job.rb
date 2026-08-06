module Search
  class DeliverNotificationJob < ApplicationJob
    MAX_ATTEMPTS = 8

    def perform(delivery_id)
      delivery = NotificationDelivery.find(delivery_id)
      retry_at = nil
      delivery.with_lock do
        return if delivery.status.in?(%w[delivered dead])

        delivery.claim!
        delivery.notification_batch.update!(state: "delivering") if delivery.notification_batch.state == "closed"
        begin
          delivery.delivered!(provider_response: deliver_email(delivery))
        rescue => error
          terminal = delivery.attempt_count >= MAX_ATTEMPTS
          if terminal
            delivery.dead!(error: "#{error.class}: #{error.message}")
          else
            retry_at = Time.current + [ 2**delivery.attempt_count, 3600 ].min.seconds
            delivery.retry_later!(error: "#{error.class}: #{error.message}", at: retry_at)
          end
        end
      end

      if retry_at
        self.class.set(wait_until: retry_at).perform_later(delivery.id)
      else
        finish_batch_if_terminal(delivery.notification_batch)
      end
    end

    private

    def deliver_email(delivery)
      SavedSearchAlertMailer.with(batch_id: delivery.notification_batch_id).matches.deliver_now
      { "provider" => "action_mailer" }
    end

    def finish_batch_if_terminal(batch)
      batch.with_lock do
        deliveries = batch.notification_deliveries.reload
        return if deliveries.where(status: %w[pending delivering failed]).exists?

        failed = deliveries.where(status: "dead").exists?
        state = failed ? "dead" : "delivered"
        batch.update!(state: state)
        batch.saved_search_matches.update_all(state: state, updated_at: Time.current)
      end
    end
  end
end
