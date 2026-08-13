class Metrics::SyncMetaAnalyticsJob < Metrics::MetaJob
  def perform
    return Rails.logger.warn("[Meta] credentials are not configured") if meta_config.blank?

    configured_accounts.each do |platform, account_key, settings|
      sync_account(platform, account_key, settings)
    rescue *ACCOUNT_SYNC_ERRORS => error
      Rails.logger.warn(
        "[Meta] #{platform}/#{account_key} failed; retrying separately: #{error.message}"
      )
      enqueue_account_retry(platform, account_key, settings)
    end

    needs_backfill = configured_accounts.any? do |platform, account_key, _settings|
      account = Metrics::MetaAccount.find_by(platform: platform, account_key: account_key)
      account && !account.media_backfilled_at?
    end
    Metrics::BackfillMetaMediaJob.perform_later if needs_backfill
  end

  private

  def enqueue_account_retry(platform, account_key, settings)
    retry_job_class.perform_later(platform, account_key, settings.to_h)
  rescue ActiveJob::EnqueueError => error
    Rails.logger.error(
      "[Meta] could not enqueue retry for #{platform}/#{account_key}: #{error.message}"
    )
  end

  def retry_job_class
    Metrics::SyncMetaAccountJob
  end

  def sync_account(platform, account_key, settings)
    if settings[:id].blank? || access_token_for(settings).blank?
      return Rails.logger.warn("[Meta] skipped #{platform}/#{account_key}: id or access token is missing")
    end

    sync = Metrics::MetaAnalyticsSync.new(client: client_for(platform, settings))
    account = sync.sync_account!(
      platform: platform,
      account_key: account_key,
      platform_account_id: settings[:id].to_s,
      account_metrics: configured_metrics(settings, :account_metrics, platform)
    )
    sync.discover_recent_media!(account)
  end
end
