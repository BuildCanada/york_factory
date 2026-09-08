class Metrics::SyncMetaAccountJob < Metrics::MetaJob
  def perform(platform, account_key, settings)
    settings = settings.with_indifferent_access
    if settings[:id].blank? || access_token_for(settings).blank?
      return Rails.logger.warn(
        "[Meta] skipped #{platform}/#{account_key}: id or access token is missing"
      )
    end

    sync = Metrics::MetaAnalyticsSync.new(
      client: client_for(platform, settings),
      time_zone: time_zone_for(settings)
    )
    account = sync.sync_account!(
      platform: platform,
      account_key: account_key,
      platform_account_id: settings[:id].to_s,
      account_metrics: configured_metrics(settings, :account_metrics, platform)
    )
    sync.discover_recent_media!(account)
    Metrics::BackfillMetaMediaJob.perform_later unless account.media_backfilled_at?
  end
end
