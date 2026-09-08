class SyncSubstackSubscribersJob < ApplicationJob
  include ActiveJob::Continuable

  BATCH_SIZE = 500

  queue_as :default
  limits_concurrency key: ->(*) { "substack-subscriber-sync" }, to: 1

  retry_on Metrics::SubstackClient::RateLimitError,
    wait: :polynomially_longer, attempts: 8
  retry_on Metrics::SubstackClient::Error,
    wait: :polynomially_longer, attempts: 5

  def perform(email_domain: nil)
    return Rails.logger.warn("[Substack] subscriber sync credentials are not configured") unless configured?

    step :import_subscribers, start: 0 do |step|
      loop do
        subscribers = next_batch(step.cursor, email_domain: email_domain)
        break if subscribers.empty?

        import_id = importer.import!(subscribers)
        mark_synced!(subscribers, import_id)
        step.advance! from: subscribers.last.id
      end
    end
  end

  private

  def next_batch(cursor, email_domain:)
    scope = Subscriber.not_synced_to_substack
      .where("id >= ?", cursor)
      .order(:id)
      .limit(batch_size)
    scope = scope.where("LOWER(email) LIKE ?", "%@#{email_domain.downcase}") if email_domain.present?
    scope.to_a
  end

  def mark_synced!(subscribers, import_id)
    now = Time.current
    Subscriber.where(id: subscribers.map(&:id), substack_synced_at: nil).update_all(
      substack_synced_at: now,
      substack_import_id: import_id,
      updated_at: now
    )
  end

  def importer
    @importer ||= SubstackSubscriberImporter.new(
      client: Metrics::SubstackClient.new(
        base_url: settings.fetch(:url),
        cookies: settings.fetch(:cookies)
      )
    )
  end

  def configured?
    settings[:url].present? && settings[:cookies].present?
  end

  def settings
    @settings ||= begin
      config = Rails.application.credentials.dig(:substack, :accounts, :build_canada)
      config.present? ? config.with_indifferent_access : {}.with_indifferent_access
    end
  end

  def batch_size
    BATCH_SIZE
  end
end
