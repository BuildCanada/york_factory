# Authentication for the public data API (WS-D controllers) and the MCP
# endpoint (WS-G). Accepts an API key or an OAuth access token issued for
# this resource (Keys::Authenticate), falls back to an anonymous read:public
# caller when nothing is presented and the surface allows it (D11,
# switchable with PUBLIC_API_ANONYMOUS=false), and answers failures as
# RFC 9457 problem+json (docs/public-interface-design.md §3.9) with an
# RFC 6750 challenge that names the RFC 9728 resource metadata, as MCP
# 2026-07-28 requires.
#
#   class PublicApi::V1::BaseController < ActionController::API
#     include PublicApiAuthentication
#     before_action -> { authenticate_public_api!(scopes: ["read:public"]) }
#   end
#
#   class PublicApi::V1::UsageController < PublicApi::V1::BaseController
#     before_action -> { require_api_scope!("usage:read") }
#   end
#
#   class McpController < ActionController::API
#     include PublicApiAuthentication
#     before_action -> { authenticate_public_api!(resource: :mcp, anonymous: false) }
#   end
module PublicApiAuthentication
  extend ActiveSupport::Concern

  PROBLEM_BASE = "https://data.buildcanada.com/api/problems".freeze

  FAILURES = {
    missing: [ 401, "unauthenticated", "Authentication required", "Send an API key or OAuth access token as Authorization: Bearer …" ],
    malformed: [ 401, "unauthenticated", "Invalid API key", "The key is malformed or mistyped (its checksum doesn't match)." ],
    unknown: [ 401, "unauthenticated", "Invalid API key", "No key matches the one presented." ],
    revoked: [ 401, "unauthenticated", "API key revoked", "This key has been revoked." ],
    expired: [ 401, "unauthenticated", "API key expired", "This key has expired or its rotation grace period has ended." ],
    invalid_token: [ 401, "unauthenticated", "Invalid access token", "No live access token matches the one presented." ],
    token_expired: [ 401, "unauthenticated", "Access token expired", "The access token has expired. Refresh it or authorize again." ],
    token_revoked: [ 401, "unauthenticated", "Access token revoked", "The access token has been revoked." ],
    wrong_audience: [ 401, "unauthenticated", "Access token not for this resource", "The access token was issued for a different resource (RFC 8707)." ],
    suspended: [ 403, "account_suspended", "Account suspended", "The account that owns this key or token is suspended." ],
    ip_not_allowed: [ 403, "ip_not_allowed", "IP address not allowed", "This key is restricted to other IP addresses." ],
    origin_not_allowed: [ 403, "origin_not_allowed", "Origin not allowed", "This key is restricted to other origins." ]
  }.freeze

  included do
    helper_method :current_api_caller if respond_to?(:helper_method)
  end

  def self.anonymous_allowed?
    setting = ENV["PUBLIC_API_ANONYMOUS"]
    setting.nil? || ActiveModel::Type::Boolean.new.cast(setting)
  end

  private

  def current_api_caller = @current_api_caller

  # resource: :rest (https://data.buildcanada.com/v1) or :mcp (…/mcp). OAuth
  # tokens are accepted only if they were issued for that resource.
  def authenticate_public_api!(scopes: [], resource: :rest, anonymous: PublicApiAuthentication.anonymous_allowed?)
    @public_api_resource = resource
    raw = public_api_bearer_token
    if raw.blank? && anonymous
      @current_api_caller = Keys::Caller.anonymous
      return require_api_scope!(*scopes)
    end

    result = Keys::Authenticate.call(raw, resource: Oauth::Settings.resource(resource, request), scopes:,
      ip: request.remote_ip, origin: request.headers["Origin"])
    if result.error == :insufficient_scope
      @current_api_caller = result.caller
      return render_insufficient_scope(result.missing_scopes)
    end
    return render_key_failure(result.error) unless result.ok?

    @current_api_caller = result.caller
  end

  def require_api_scope!(*scopes)
    missing = scopes.map(&:to_s).reject { |scope| current_api_caller&.scope?(scope) }
    render_insufficient_scope(missing) if missing.any?
  end

  def public_api_bearer_token
    scheme, token = request.headers["Authorization"].to_s.split(" ", 2)
    token.to_s.strip if scheme&.casecmp?("Bearer")
  end

  def public_api_resource = @public_api_resource || :rest

  def resource_metadata_url = Oauth::Settings.resource_metadata_url(public_api_resource, request)

  def render_key_failure(error)
    status, code, title, detail = FAILURES.fetch(error)
    if error == :missing
      response.headers["WWW-Authenticate"] = bearer_challenge(scope: Oauth::Settings::DEFAULT_SCOPES.join(" "))
    elsif status == 401
      response.headers["WWW-Authenticate"] = bearer_challenge(error: "invalid_token", error_description: title)
    end
    render_api_problem(status:, code:, title:, detail:)
  end

  def render_insufficient_scope(scopes)
    scope = Array(scopes).join(" ")
    if current_api_caller.nil? || current_api_caller.anonymous?
      response.headers["WWW-Authenticate"] = bearer_challenge(scope:)
      return render_api_problem(status: 401, code: "unauthenticated", title: "Authentication required",
        detail: "This operation needs an API key or OAuth token with #{scope}.", required_scope: scope)
    end

    response.headers["WWW-Authenticate"] = bearer_challenge(error: "insufficient_scope", scope:)
    render_api_problem(status: 403, code: "insufficient_scope", title: "Insufficient scope",
      detail: "This #{current_api_caller.oauth? ? 'token' : 'key'} lacks #{scope}.", required_scope: scope)
  end

  # RFC 6750 §3 and RFC 9728 §5.1.
  def bearer_challenge(**params)
    attributes = params.compact.merge(resource_metadata: resource_metadata_url)
    "Bearer " + attributes.map { |key, value| %(#{key}="#{value.to_s.delete('"\\')}") }.join(", ")
  end

  def render_api_problem(status:, code:, title:, detail:, **extra)
    body = { type: "#{PROBLEM_BASE}/#{code.dasherize}", title:, status:, detail:, instance: request.request_id, code:, **extra }
    render json: body, status:, content_type: "application/problem+json"
  end
end
