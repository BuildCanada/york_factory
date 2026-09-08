class Metrics::MetaJob < ApplicationJob
  queue_as :default

  ACCOUNT_SYNC_ERRORS = [
    Metrics::MetaGraphClient::Error,
    ActiveRecord::ActiveRecordError,
    KeyError
  ].freeze

  retry_on(*ACCOUNT_SYNC_ERRORS,
    wait: :polynomially_longer, attempts: 5
  )

  private

  def meta_config
    @meta_config ||= begin
      value = Rails.application.credentials.dig(:meta)
      value.present? ? value.with_indifferent_access : {}.with_indifferent_access
    end
  end

  def configured_accounts
    meta_config.fetch(:accounts, {}).flat_map do |platform, accounts|
      accounts.map do |account_key, settings|
        [ platform.to_s, account_key.to_s, settings.with_indifferent_access ]
      end
    end
  end

  def settings_for(account)
    meta_config.dig(:accounts, account.platform, account.account_key)&.with_indifferent_access ||
      {}.with_indifferent_access
  end

  def configured_metrics(settings, key, platform)
    return Array(settings[key]) if settings.key?(key)

    defaults = key == :account_metrics ?
      Metrics::MetaAnalyticsSync::DEFAULT_ACCOUNT_METRICS :
      Metrics::MetaAnalyticsSync::DEFAULT_MEDIA_METRICS
    defaults.fetch(platform)
  end

  # Instagram buckets account insights on the account's own calendar day. Allow a
  # per-account override, then a global one, before the service default.
  def time_zone_for(settings)
    settings[:time_zone].presence || meta_config[:time_zone].presence ||
      Metrics::MetaAnalyticsSync::DEFAULT_INSIGHTS_TIME_ZONE
  end

  def client_for(platform, settings)
    access_token = access_token_for(settings)
    raise Metrics::MetaGraphClient::Error, "Meta access token is missing" if access_token.blank?

    system_client = Metrics::MetaGraphClient.new(
      access_token: access_token,
      api_version: api_version
    )
    return system_client unless platform == "facebook"

    Metrics::MetaGraphClient.new(
      access_token: system_client.page_access_token(settings.fetch(:id)),
      api_version: api_version
    )
  end

  def api_version
    meta_config[:api_version].presence || ENV["META_GRAPH_API_VERSION"].presence ||
      Metrics::MetaGraphClient::DEFAULT_API_VERSION
  end

  def access_token_for(settings)
    settings[:access_token].presence || meta_config[:access_token].presence ||
      ENV["META_ACCESS_TOKEN"].presence
  end
end
