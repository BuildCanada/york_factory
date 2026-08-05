require "openssl"

module Search
  class DeliverNotificationJob < ApplicationJob
    MAX_ATTEMPTS = 8
    RETRYABLE_STATUSES = [ 408, 409, 425, 429 ].freeze
    WEBHOOK_HTTP_OPTIONS = {
      timeout: { connect_timeout: 5, operation_timeout: 15 }
    }.freeze

    def perform(delivery_id)
      delivery = NotificationDelivery.find(delivery_id)
      retry_at = nil
      delivery.with_lock do
        return if delivery.status.in?(%w[delivered dead])

        delivery.claim!
        delivery.notification_batch.update!(state: "delivering") if delivery.notification_batch.state == "closed"
        begin
          response = delivery.channel == "email" ? deliver_email(delivery) : deliver_webhook(delivery)
          delivery.delivered!(provider_response: response)
        rescue => error
          terminal = delivery.attempt_count >= MAX_ATTEMPTS || permanent?(error)
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

    def deliver_webhook(delivery)
      saved_search = delivery.notification_batch.saved_search
      url = saved_search.delivery_configuration.fetch("webhook_url")
      safe_url = validate_webhook_url(url)
      uri = URI.parse(safe_url)
      raise "webhook URL must use HTTPS" unless uri.scheme == "https"

      body = JSON.generate(delivery.notification_batch.payload)
      timestamp = Time.current.to_i.to_s
      signature = OpenSSL::HMAC.hexdigest(
        "SHA256",
        saved_search.webhook_secret.to_s,
        "#{timestamp}.#{body}"
      )
      response = webhook_http.post(
        safe_url,
        headers: {
          "Content-Type" => "application/json",
          "X-BuildCanada-Delivery" => delivery.idempotency_key,
          "X-BuildCanada-Timestamp" => timestamp,
          "X-BuildCanada-Signature" => "v1=#{signature}"
        },
        body: body
      )
      raise(response.error || "webhook request failed") unless response.respond_to?(:status)

      status = response.status.to_i
      unless status.between?(200, 299)
        error = WebhookResponseError.new(status)
        raise error
      end

      { "status" => status, "request_id" => response["x-request-id"] }.compact
    end

    def webhook_http
      @webhook_http ||= HTTPX.with(**WEBHOOK_HTTP_OPTIONS)
    end

    def validate_webhook_url(url)
      SafeUrl.validate_public!(url)
    end

    def permanent?(error)
      error.is_a?(WebhookResponseError) && !RETRYABLE_STATUSES.include?(error.status) && error.status < 500
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

    class WebhookResponseError < StandardError
      attr_reader :status

      def initialize(status)
        @status = status
        super("webhook returned HTTP #{status}")
      end
    end
  end
end
