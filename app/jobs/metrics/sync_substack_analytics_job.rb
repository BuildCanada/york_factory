class Metrics::SyncSubstackAnalyticsJob < Metrics::SubstackJob
  def perform
    return Rails.logger.warn("[Substack] credentials are not configured") if substack_config.blank?

    configured_accounts.each do |account_key, settings|
      sync_account(account_key, settings)
    end

    needs_backfill = configured_accounts.any? do |account_key, _settings|
      publication = Metrics::SubstackPublication.find_by(account_key: account_key)
      publication && !publication.posts_backfilled_at?
    end
    Metrics::BackfillSubstackPostsJob.perform_later if needs_backfill
  end

  private

  def sync_account(account_key, settings)
    if settings[:url].blank?
      return Rails.logger.warn("[Substack] skipped #{account_key}: URL is missing")
    end

    sync = Metrics::SubstackAnalyticsSync.new(client: client_for(settings))
    publication = sync.sync_publication!(account_key: account_key, url: settings[:url])
    sync.discover_recent_posts!(publication)
    sync.sync_publication_traffic!(publication) if settings[:cookies].present?
  end
end
