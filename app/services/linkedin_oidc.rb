require "jwt"
require "json"
require "securerandom"
require "openssl"

class LinkedinOidc
  AUTHORIZE_URL = "https://www.linkedin.com/oauth/v2/authorization"
  TOKEN_URL     = "https://www.linkedin.com/oauth/v2/accessToken"
  JWKS_URL      = "https://www.linkedin.com/oauth/openid/jwks"
  ISSUER        = "https://www.linkedin.com"
  SCOPES        = "openid profile email"
  JWKS_CACHE_KEY = "linkedin:jwks"
  JWKS_TTL       = 24.hours

  class Error < StandardError; end
  class ConfigError < Error; end

  def self.authorize_url(state:, nonce:)
    params = {
      response_type: "code",
      client_id:     client_id,
      redirect_uri:  redirect_uri,
      scope:         SCOPES,
      state:         state,
      nonce:         nonce
    }
    "#{AUTHORIZE_URL}?#{URI.encode_www_form(params)}"
  end

  def self.exchange_code(code)
    response = HTTPX.post(
      TOKEN_URL,
      form: {
        grant_type:    "authorization_code",
        code:          code,
        redirect_uri:  redirect_uri,
        client_id:     client_id,
        client_secret: client_secret
      }
    ).raise_for_status
    JSON.parse(response.body.to_s)
  rescue HTTPX::HTTPError => e
    raise Error, "LinkedIn token exchange failed: HTTP #{e.response.status}"
  end

  def self.verify_id_token(id_token, nonce:)
    payload, _header = JWT.decode(
      id_token,
      nil,
      true,
      algorithms: %w[RS256],
      iss: ISSUER,
      verify_iss: true,
      aud: client_id,
      verify_aud: true,
      verify_iat: true,
      jwks: jwks_loader
    )
    raise Error, "Nonce mismatch" unless payload["nonce"] == nonce
    payload
  end

  # Public so the controller can render it for the popup origin filter.
  def self.client_id
    ENV.fetch("LINKEDIN_CLIENT_ID") { raise ConfigError, "LINKEDIN_CLIENT_ID not set" }
  end

  def self.client_secret
    ENV.fetch("LINKEDIN_CLIENT_SECRET") { raise ConfigError, "LINKEDIN_CLIENT_SECRET not set" }
  end

  def self.redirect_uri
    ENV.fetch("LINKEDIN_REDIRECT_URI") { raise ConfigError, "LINKEDIN_REDIRECT_URI not set" }
  end

  def self.postmessage_origin
    ENV.fetch("LINKEDIN_POSTMESSAGE_ORIGIN") { raise ConfigError, "LINKEDIN_POSTMESSAGE_ORIGIN not set" }
  end

  def self.jwks_loader
    ->(options) {
      keys = Rails.cache.fetch(JWKS_CACHE_KEY, expires_in: JWKS_TTL, force: options[:invalidate]) do
        fetch_jwks
      end
      { keys: keys }
    }
  end

  def self.fetch_jwks
    response = HTTPX.get(JWKS_URL).raise_for_status
    JSON.parse(response.body.to_s).fetch("keys")
  rescue HTTPX::HTTPError => e
    raise Error, "JWKS fetch failed: HTTP #{e.response.status}"
  end
end
