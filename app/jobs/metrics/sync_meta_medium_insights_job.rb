class Metrics::SyncMetaMediumInsightsJob < Metrics::MetaJob
  def perform(medium, scheduled_for:)
    medium.with_lock do
      return unless medium.next_insights_sync_at == scheduled_for
    end

    settings = settings_for(medium.account)
    sync = Metrics::MetaAnalyticsSync.new(
      client: client_for(medium.account.platform, settings),
      now: scheduled_for
    )
    sync.sync_media_insights!(
      medium,
      metric_names: configured_metrics(settings, :media_metrics, medium.account.platform)
    )
    medium.mark_insights_synced!(scheduled_for: scheduled_for)
  end
end
