module Oauth
  # Where the OAuth 2.1 pieces of docs/public-interface-design.md §4.6 live,
  # and the numbers they use.
  #
  # In production the authorization server is https://auth.buildcanada.com
  # and the protected resources are on https://data.buildcanada.com. Both can
  # be overridden (OAUTH_ISSUER, PUBLIC_DATA_ORIGIN, or credentials
  # oauth.issuer and oauth.data_origin), for staging. Elsewhere both default
  # to the origin of the request being served, so development and test need
  # no setup and one host plays both roles.
  module Settings
    PRODUCTION_ISSUER = "https://auth.buildcanada.com".freeze
    PRODUCTION_DATA_ORIGIN = "https://data.buildcanada.com".freeze
    FALLBACK_ORIGIN = "http://localhost:3000".freeze

    # The protected resources (RFC 8707 resource indicators). A token is
    # bound to exactly one of them.
    RESOURCE_PATHS = { mcp: "/mcp", rest: "/v1" }.freeze

    # Scopes OAuth clients may ask for. keys:manage (phase 2) and cms:drafts
    # (the CMS, acting as the user) are not offered to third-party clients.
    SCOPES = %w[read:public read:persons usage:read].freeze
    # What a client gets when it asks for nothing, and the scope named in a
    # 401 challenge. read:persons is asked for by step-up, when a tool needs it.
    DEFAULT_SCOPES = %w[read:public usage:read].freeze

    # Plain-word descriptions for the consent screen.
    SCOPE_DESCRIPTIONS = {
      "read:public" => "Read Build Canada's public data: organizations, spending, documents, releases and datasets.",
      "read:persons" => "Read people named in public records, such as corporate directors and people with significant control: their names, public roles, city, province and postal area.",
      "usage:read" => "See your account's API usage."
    }.freeze
    PERSONS_NOTE = "Never includes a street address.".freeze

    ACCESS_TOKEN_LIFETIME = 1.hour
    # A refresh token not used for this long stops working. Each refresh
    # issues a new one, so an app in use stays signed in.
    REFRESH_TOKEN_IDLE_LIFETIME = 30.days

    module_function

    def issuer(request = nil)
      configured("OAUTH_ISSUER", :issuer) || (Rails.env.production? ? PRODUCTION_ISSUER : origin_of(request))
    end

    def data_origin(request = nil)
      configured("PUBLIC_DATA_ORIGIN", :data_origin) || (Rails.env.production? ? PRODUCTION_DATA_ORIGIN : origin_of(request))
    end

    def resource(kind, request = nil) = "#{data_origin(request)}#{RESOURCE_PATHS.fetch(kind)}"

    def resources(request = nil) = RESOURCE_PATHS.keys.map { |kind| resource(kind, request) }

    # RFC 9728 §3.1: the metadata URL for a resource with a path inserts the
    # path after the well-known segment.
    def resource_metadata_url(kind, request = nil)
      "#{data_origin(request)}/.well-known/oauth-protected-resource#{RESOURCE_PATHS.fetch(kind)}"
    end

    def authorization_server_metadata_url(request = nil) = "#{issuer(request)}/.well-known/oauth-authorization-server"

    # The canonical form of a resource indicator (RFC 8707 §2, MCP "Canonical
    # Server URI"): an absolute http(s) URI with no fragment, query or user
    # info, a lowercase scheme and host, no default port and no trailing
    # slash. nil when the value can't be one.
    def canonical_resource(value)
      uri = URI.parse(value.to_s.strip)
      return unless uri.is_a?(URI::HTTP) && uri.host.present?
      return if uri.fragment || uri.query || uri.userinfo

      port = uri.port == uri.default_port ? "" : ":#{uri.port}"
      "#{uri.scheme.downcase}://#{uri.host.downcase}#{port}#{uri.path.chomp('/')}"
    rescue URI::InvalidURIError
      nil
    end

    def origin_of(request)
      return FALLBACK_ORIGIN unless request

      request.base_url
    end

    def configured(env, credential)
      ENV[env].presence&.chomp("/") || Rails.application.credentials.dig(:oauth, credential).presence&.chomp("/")
    end
  end
end
