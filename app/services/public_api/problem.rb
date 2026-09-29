module PublicApi
  # An RFC 9457 problem (docs/public-interface-design.md §3.9, the contract's
  # components/problems.yaml). Raise one anywhere under a /v1 controller; the
  # base controller renders it as application/problem+json with the request's
  # ID as `instance`.
  class Problem < StandardError
    TYPE_BASE = "https://data.buildcanada.com/problems".freeze
    ERRORS_DOCS = "https://data.buildcanada.com/docs/concepts/errors.md".freeze
    LIMITS_DOCS = "https://data.buildcanada.com/docs/concepts/rate-limits.md".freeze
    UPGRADE_URL = "https://auth.buildcanada.com/developers/plan".freeze
    BULK_URL = "https://data.buildcanada.com/v1/exports".freeze

    CODES = {
      "invalid_parameter" => [ 400, "Invalid parameter" ],
      "unauthenticated" => [ 401, "Authentication required" ],
      "insufficient_scope" => [ 403, "Insufficient scope" ],
      "account_suspended" => [ 403, "Account suspended" ],
      "ip_not_allowed" => [ 403, "IP address not allowed" ],
      "origin_not_allowed" => [ 403, "Origin not allowed" ],
      "not_found" => [ 404, "Not found" ],
      "not_yet_published" => [ 404, "Not yet published" ],
      "redirected" => [ 301, "Entity redirected" ],
      "release_mismatch" => [ 409, "Cursor from another release" ],
      "retired" => [ 410, "Retired" ],
      "query_too_broad" => [ 422, "Query too broad" ],
      "rate_limited" => [ 429, "Rate limit exceeded" ],
      "quota_exceeded" => [ 429, "Monthly quota exceeded" ],
      "internal_error" => [ 500, "Internal error" ],
      "release_building" => [ 503, "Release building" ]
    }.freeze

    attr_reader :code, :status, :title, :extra, :headers

    def initialize(code, detail, title: nil, headers: {}, **extra)
      @code = code.to_s
      @status, default_title = CODES.fetch(@code)
      @title = title || default_title
      @extra = extra.compact
      @headers = headers
      super(detail)
    end

    def detail = message

    def self.invalid(errors)
      errors = errors.is_a?(Hash) ? [ errors ] : Array(errors)
      detail = errors.one? ? "#{errors.first[:parameter]}: #{errors.first[:detail]}" : "#{errors.size} parameters are invalid."
      new(:invalid_parameter, detail, errors:)
    end

    def self.not_found(detail) = new(:not_found, detail)

    # 429 rate_limited or quota_exceeded, from a refused PublicApi::RateLimiter
    # charge. Shared by /v1 and /mcp.
    def self.rate_limited(result, caller:)
      plan = caller.plan.name
      who = caller.anonymous? ? "Your IP address" : "Key #{caller.api_key&.token_prefix}…"
      who = "This OAuth authorization" if caller.oauth?
      if result.code == "quota_exceeded"
        period = result.allowance.name == "day" ? "today" : "this month"
        detail = "#{who} used #{result.allowance_used} of #{result.allowance.quota} request units #{period}."
      else
        detail = "#{who} used #{result.minute_used} of #{result.minute.quota} request units in the current 60-second window."
      end
      new(result.code, detail, headers: { "Retry-After" => result.retry_after.to_s },
        retry_after_seconds: result.retry_after, plan: plan == "paid" ? "paid" : plan, upgrade_url: UPGRADE_URL, bulk_url: BULK_URL)
    end

    def body(instance:)
      docs = %w[rate_limited quota_exceeded].include?(code) ? LIMITS_DOCS : ERRORS_DOCS
      { type: "#{TYPE_BASE}/#{code.dasherize}", title:, status:, detail:, instance:, code:, docs:, **extra }
    end
  end
end
