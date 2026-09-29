# Key authentication for the public data API (WS-D controllers) and the MCP
# endpoint (WS-G). Verifies the bearer key with Keys::Verify, falls back to
# an anonymous read:public caller when no key is presented (D11, switchable
# with PUBLIC_API_ANONYMOUS=false), and answers failures as RFC 9457
# problem+json (docs/public-interface-design.md §3.9).
#
#   class PublicApi::V1::BaseController < ActionController::API
#     include PublicApiAuthentication
#     before_action -> { authenticate_public_api!(scopes: ["read:public"]) }
#   end
#
#   class PublicApi::V1::UsageController < PublicApi::V1::BaseController
#     before_action -> { require_api_scope!("usage:read") }
#   end
module PublicApiAuthentication
  extend ActiveSupport::Concern

  PROBLEM_BASE = "https://data.buildcanada.com/api/problems".freeze

  FAILURES = {
    missing: [ 401, "unauthenticated", "Authentication required", "Send an API key as Authorization: Bearer bc_live_…" ],
    malformed: [ 401, "unauthenticated", "Invalid API key", "The key is malformed or mistyped (its checksum doesn't match)." ],
    unknown: [ 401, "unauthenticated", "Invalid API key", "No key matches the one presented." ],
    revoked: [ 401, "unauthenticated", "API key revoked", "This key has been revoked." ],
    expired: [ 401, "unauthenticated", "API key expired", "This key has expired or its rotation grace period has ended." ],
    suspended: [ 403, "account_suspended", "Account suspended", "The account that owns this key is suspended." ],
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

  def authenticate_public_api!(scopes: [])
    raw = public_api_bearer_token
    if raw.blank? && PublicApiAuthentication.anonymous_allowed?
      @current_api_caller = Keys::Caller.anonymous
      return require_api_scope!(*scopes)
    end

    result = Keys::Verify.call(raw, scopes:, ip: request.remote_ip, origin: request.headers["Origin"])
    if result.error == :insufficient_scope
      @current_api_caller = Keys::Caller.for(result.api_key)
      return render_insufficient_scope(result.required_scope)
    end
    return render_key_failure(result.error) unless result.ok?

    @current_api_caller = result.caller
  end

  def require_api_scope!(*scopes)
    missing = scopes.map(&:to_s).find { |scope| !current_api_caller&.scope?(scope) }
    render_insufficient_scope(missing) if missing
  end

  def public_api_bearer_token
    scheme, token = request.headers["Authorization"].to_s.split(" ", 2)
    token.to_s.strip if scheme&.casecmp?("Bearer")
  end

  def render_key_failure(error)
    status, code, title, detail = FAILURES.fetch(error)
    response.headers["WWW-Authenticate"] = %(Bearer error="invalid_token") if status == 401 && error != :missing
    response.headers["WWW-Authenticate"] = "Bearer" if error == :missing
    render_api_problem(status:, code:, title:, detail:)
  end

  def render_insufficient_scope(scope)
    response.headers["WWW-Authenticate"] = %(Bearer error="insufficient_scope", scope="#{scope}")
    if current_api_caller.nil? || current_api_caller.anonymous?
      return render_api_problem(status: 401, code: "unauthenticated", title: "Authentication required",
        detail: "This operation needs an API key with #{scope}.", required_scope: scope)
    end

    render_api_problem(status: 403, code: "insufficient_scope", title: "Insufficient scope",
      detail: "This key lacks the #{scope} scope.", required_scope: scope)
  end

  def render_api_problem(status:, code:, title:, detail:, **extra)
    body = { type: "#{PROBLEM_BASE}/#{code.dasherize}", title:, status:, detail:, instance: request.request_id, code:, **extra }
    render json: body, status:, content_type: "application/problem+json"
  end
end
