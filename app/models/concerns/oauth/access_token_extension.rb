module Oauth
  # Public-API behaviour for Doorkeeper::AccessToken (included from
  # config/initializers/doorkeeper.rb). A public-API token has a resource,
  # its audience (RFC 8707), and an account that its usage is billed to.
  # First-party (TradingPost) tokens have neither.
  module AccessTokenExtension
    extend ActiveSupport::Concern

    included do
      belongs_to :account, optional: true

      scope :public_api, -> { where.not(resource: nil) }
      # Tokens an app could still use: the access token is live, or the
      # refresh token is (not revoked and used within the idle lifetime).
      scope :usable, ->(now = Time.current) {
        where(revoked_at: nil).where(
          "oauth_access_tokens.created_at + (oauth_access_tokens.expires_in * interval '1 second') > :now " \
          "OR (oauth_access_tokens.refresh_token IS NOT NULL AND oauth_access_tokens.created_at > :idle)",
          now:, idle: now - Oauth::Settings::REFRESH_TOKEN_IDLE_LIFETIME
        )
      }
    end

    def public_api? = resource.present?

    # A refresh token lives until it goes unused for the idle lifetime. Each
    # refresh creates a new token row, so created_at is the last refresh.
    def refresh_idle_expired?(now = Time.current)
      public_api? && created_at <= now - Oauth::Settings::REFRESH_TOKEN_IDLE_LIFETIME
    end

    # :mcp or :rest, from the resource's path.
    def resource_kind
      return unless public_api?

      Oauth::Settings::RESOURCE_PATHS.key(URI.parse(resource).path)
    rescue URI::InvalidURIError
      nil
    end
  end
end
