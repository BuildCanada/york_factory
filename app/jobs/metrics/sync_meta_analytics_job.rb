class Metrics::SyncMetaAnalyticsJob < ApplicationJob
  queue_as :default

  retry_on Metrics::MetaGraphClient::Error,
    wait: :polynomially_longer, attempts: 5

  def perform
    return Rails.logger.warn("[Meta] credentials are not configured") if config.blank?

    configured_accounts.each do |platform, account_key, settings|
      sync_account(platform, account_key, settings)
    end
  end

  private

  def sync_account(platform, account_key, settings)
    access_token = settings[:access_token].presence || config[:access_token].presence || ENV["META_ACCESS_TOKEN"].presence
    if access_token.blank? || settings[:id].blank?
      return Rails.logger.warn("[Meta] skipped #{platform}/#{account_key}: id or access token is missing")
    end

    system_client = Metrics::MetaGraphClient.new(
      access_token: access_token,
      api_version: api_version
    )
    client = if platform == "facebook"
      Metrics::MetaGraphClient.new(
        access_token: system_client.page_access_token(settings[:id]),
        api_version: api_version
      )
    else
      system_client
    end
    Metrics::MetaAnalyticsSync.new(client: client).sync!(
      platform: platform,
      account_key: account_key,
      platform_account_id: settings[:id].to_s,
      account_metrics: configured_metrics(settings, :account_metrics, platform),
      media_metrics: configured_metrics(settings, :media_metrics, platform)
    )
  end

  def configured_metrics(settings, key, platform)
    return Array(settings[key]) if settings.key?(key)

    defaults = key == :account_metrics ?
      Metrics::MetaAnalyticsSync::DEFAULT_ACCOUNT_METRICS :
      Metrics::MetaAnalyticsSync::DEFAULT_MEDIA_METRICS
    defaults.fetch(platform)
  end

  def api_version
    config[:api_version].presence || ENV["META_GRAPH_API_VERSION"].presence ||
      Metrics::MetaGraphClient::DEFAULT_API_VERSION
  end

  def configured_accounts
    config.fetch(:accounts, {}).flat_map do |platform, accounts|
      accounts.map do |account_key, settings|
        [ platform.to_s, account_key.to_s, settings.with_indifferent_access ]
      end
    end
  end

  def config
    @config ||= begin
      value = Rails.application.credentials.dig(:meta)
      value.present? ? value.with_indifferent_access : {}.with_indifferent_access
    end
  end
end
