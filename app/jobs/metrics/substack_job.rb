class Metrics::SubstackJob < ApplicationJob
  queue_as :default

  retry_on Metrics::SubstackClient::RateLimitError,
    wait: :polynomially_longer, attempts: 8
  retry_on Metrics::SubstackClient::Error,
    wait: :polynomially_longer, attempts: 5

  private

  def substack_config
    @substack_config ||= begin
      value = Rails.application.credentials.dig(:substack)
      value.present? ? value.with_indifferent_access : {}.with_indifferent_access
    end
  end

  def configured_accounts
    substack_config.fetch(:accounts, {}).map do |account_key, settings|
      [ account_key.to_s, settings.with_indifferent_access ]
    end
  end

  def settings_for(publication)
    substack_config.dig(:accounts, publication.account_key)&.with_indifferent_access ||
      {}.with_indifferent_access
  end

  def client_for(settings)
    Metrics::SubstackClient.new(
      base_url: settings.fetch(:url),
      cookies: settings[:cookies]
    )
  end
end
