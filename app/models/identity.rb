class Identity < ApplicationRecord
  # Refresh in the background via active_job-performs (identity.refresh_later).
  performs :refresh!

  encrypts :access_token
  encrypts :refresh_token

  belongs_to :user

  validates :provider, presence: true
  validates :uid, presence: true, uniqueness: { scope: :provider }

  # OAuth token endpoints keyed by provider.
  TOKEN_ENDPOINTS = {
    "linkedin" => "https://www.linkedin.com/oauth/v2/accessToken",
    "google_oauth2" => "https://oauth2.googleapis.com/token"
  }.freeze

  def token_expired?
    token_expires_at.present? && token_expires_at.past?
  end

  # A usable access token, refreshing first if it has expired. Returns nil when
  # there is no token (or the refresh failed).
  def fresh_access_token
    refresh! if token_expired? && refresh_token.present?
    access_token
  end

  # Exchanges the refresh_token for a new access_token at the provider's token
  # endpoint and persists the result. Returns true on success, false otherwise
  # (no refresh_token, unsupported provider, missing client creds, or an error
  # response). Never raises — safe to call from a job.
  def refresh!
    return false if refresh_token.blank?

    endpoint = TOKEN_ENDPOINTS[provider]
    client_id, client_secret = self.class.client_credentials(provider)
    return false if endpoint.blank? || client_id.blank? || client_secret.blank?

    response = Net::HTTP.post_form(URI(endpoint),
      "grant_type" => "refresh_token",
      "refresh_token" => refresh_token,
      "client_id" => client_id,
      "client_secret" => client_secret)
    return false unless response.is_a?(Net::HTTPSuccess)

    data = JSON.parse(response.body)
    update!(
      access_token: data["access_token"],
      refresh_token: data["refresh_token"].presence || refresh_token,
      token_expires_at: data["expires_in"].present? ? Time.current + data["expires_in"].to_i.seconds : token_expires_at
    )
    true
  rescue StandardError => e
    Rails.logger.warn("[identity.refresh] #{provider} uid=#{uid} failed: #{e.class}: #{e.message}")
    false
  end

  # Client credentials used to refresh tokens, mirroring the OmniAuth setup in
  # config/initializers/devise.rb (LinkedIn from credentials, Google from ENV).
  def self.client_credentials(provider)
    case provider
    when "linkedin"
      [ Rails.application.credentials.dig(:linkedin, :client_id),
        Rails.application.credentials.dig(:linkedin, :client_secret) ]
    when "google_oauth2"
      [ ENV["GOOGLE_CLIENT_ID"], ENV["GOOGLE_CLIENT_SECRET"] ]
    else
      [ nil, nil ]
    end
  end
end
