# Re-requests account-level insights for a date range.
#
# Instagram's total_value metrics (views, total_interactions, ...) were previously
# fetched with no time range, so they landed stamped with the sync clock instead of
# a calendar day. This job re-pulls a range day by day so those days get a real
# date, and recovers days that were never captured at all.
#
#   Metrics::BackfillMetaAccountInsightsJob.perform_later(
#     platform: "instagram", account_key: "build_canada",
#     from: "2026-08-01", to: "2026-08-30"
#   )
#
# Re-running is safe: each day upserts on
# (meta_account_id, metric_name, period, observed_at).
class Metrics::BackfillMetaAccountInsightsJob < Metrics::MetaJob
  MAX_DAYS = 400

  def perform(platform:, account_key:, from:, to:, metric_names: nil)
    return Rails.logger.warn("[Meta] credentials are not configured") if meta_config.blank?

    settings = meta_config.dig(:accounts, platform, account_key)&.with_indifferent_access
    if settings.blank? || settings[:id].blank? || access_token_for(settings).blank?
      return Rails.logger.warn("[Meta] backfill skipped #{platform}/#{account_key}: not configured")
    end

    account = Metrics::MetaAccount.find_by(platform: platform, account_key: account_key)
    return Rails.logger.warn("[Meta] backfill skipped #{platform}/#{account_key}: never synced") if account.nil?

    from_date = from.to_date
    to_date = to.to_date
    if to_date < from_date
      raise ArgumentError, "backfill range ends (#{to_date}) before it starts (#{from_date})"
    end
    if (to_date - from_date).to_i + 1 > MAX_DAYS
      raise ArgumentError, "backfill range exceeds #{MAX_DAYS} days"
    end

    metrics = Array(metric_names).presence ||
      configured_metrics(settings, :account_metrics, platform)
    sync = Metrics::MetaAnalyticsSync.new(
      client: client_for(platform, settings),
      time_zone: time_zone_for(settings)
    )
    days = sync.backfill_account_insights!(account, metric_names: metrics, from: from_date, to: to_date)
    Rails.logger.info(
      "[Meta] backfilled #{days} days of account insights for #{platform}/#{account_key} " \
      "(#{from_date}..#{to_date})"
    )
    days
  end
end
