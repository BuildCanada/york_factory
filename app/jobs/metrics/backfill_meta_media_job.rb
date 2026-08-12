class Metrics::BackfillMetaMediaJob < Metrics::MetaJob
  include ActiveJob::Continuable

  def perform
    return Rails.logger.warn("[Meta] credentials are not configured") if meta_config.blank?

    configured_accounts.each do |platform, account_key, settings|
      backfill_account(platform, account_key, settings)
    end
  end

  private

  def backfill_account(platform, account_key, settings)
    step "backfill_#{platform}_#{account_key}".to_sym do |step|
      next if settings[:id].blank? || access_token_for(settings).blank?

      account = Metrics::MetaAccount.find_by(platform: platform, account_key: account_key)
      next unless account
      next if account.media_backfilled_at?

      sync = Metrics::MetaAnalyticsSync.new(client: client_for(platform, settings))
      loop do
        result = sync.discover_media_page!(account, after: step.cursor, backfill: true)
        Rails.logger.info(
          "[Meta] backfilled #{result[:processed]} posts for #{platform}/#{account_key}"
        )
        if result[:next_cursor].blank?
          account.update!(media_backfilled_at: Time.current)
          break
        end

        step.set! result[:next_cursor]
      end
    end
  end
end
