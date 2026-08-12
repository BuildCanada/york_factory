class Metrics::BackfillSubstackPostsJob < Metrics::SubstackJob
  include ActiveJob::Continuable

  def perform
    return Rails.logger.warn("[Substack] credentials are not configured") if substack_config.blank?

    configured_accounts.each do |account_key, settings|
      backfill_account(account_key, settings)
    end
  end

  private

  def backfill_account(account_key, settings)
    step "backfill_substack_#{account_key}".to_sym, start: 0 do |step|
      next if settings[:url].blank?

      publication = Metrics::SubstackPublication.find_by(account_key: account_key)
      next unless publication
      next if publication.posts_backfilled_at?

      sync = Metrics::SubstackAnalyticsSync.new(client: client_for(settings))
      loop do
        result = sync.discover_posts_page!(publication, offset: step.cursor, backfill: true)
        Rails.logger.info(
          "[Substack] backfilled #{result[:processed]} posts for #{account_key}"
        )
        if result[:next_offset].nil?
          publication.update!(posts_backfilled_at: Time.current)
          sync.sync_publication_traffic!(publication) if settings[:cookies].present?
          break
        end

        step.set! result[:next_offset]
      end
    end
  end
end
