module PublicApi
  # Request-unit limits for /v1 in this service (docs/public-interface-design.md
  # §6.1 and §6.2), so the API is limited before the data-edge Worker (WS-H)
  # exists. Once the Worker fronts the API it enforces the token bucket and the
  # quotas itself; requests it signs skip this limiter
  # (PublicApi::V1::BaseController#edge_verified?).
  #
  # Two fixed windows per caller, both counted in units:
  # - the rate: the plan's units per minute, per key (per IP when anonymous),
  #   in windows aligned to the UTC minute;
  # - the allowance: the plan's monthly units per account (UTC calendar month),
  #   or the anonymous plan's daily units per IP (UTC day). Unlimited plans
  #   have none.
  # The Worker's burst (a token bucket of 2x the rate) is not reproduced: a
  # fixed window never lets more than the rate through in a minute.
  #
  # The store is pluggable (PUBLIC_API_RATE_LIMIT_STORE): `cache` counts in
  # Rails.cache (Solid Cache in production, shared by every Puma worker and
  # host); `memory` counts in this process only; `off` never limits. The
  # default is `cache` when Rails.cache persists anything, else `memory`.
  class RateLimiter
    Policy = Data.define(:name, :quota, :seconds)

    Result = Data.define(:allowed, :code, :minute, :allowance, :minute_used, :allowance_used, :now) do
      def minute_remaining = [ minute.quota - minute_used, 0 ].max

      def minute_reset = (minute.seconds - (now.to_i % minute.seconds))

      def allowance_remaining = allowance && [ allowance.quota - allowance_used, 0 ].max

      def allowance_reset
        return nil unless allowance

        utc = now.utc
        ends = allowance.name == "day" ? utc.tomorrow.beginning_of_day : utc.next_month.beginning_of_month
        (ends - utc).ceil
      end

      def retry_after = code == "quota_exceeded" ? allowance_reset : minute_reset

      # draft-ietf-httpapi-ratelimit-headers, as the contract's headers.yaml writes them.
      def headers
        policies = [ minute, allowance ].compact.map { |p| %("#{p.name}";q=#{p.quota};w=#{p.seconds}) }
        headers = {
          "RateLimit-Policy" => policies.join(", "),
          "RateLimit" => %("minute";r=#{minute_remaining};t=#{minute_reset})
        }
        headers["BC-Quota-Remaining"] = allowance_remaining.to_s if allowance
        headers
      end
    end

    # A charge that was let through, so it can be settled once the response's
    # real cost is known (a 304 costs 0 units but counts 1 toward the rate).
    Charge = Data.define(:keys, :units, :result)

    MONTH_SECONDS = 2_592_000

    class << self
      # nil means off.
      def store
        return @store if defined?(@store)

        @store = build_store(ENV.fetch("PUBLIC_API_RATE_LIMIT_STORE", nil))
      end

      attr_writer :store

      def reset_store!
        remove_instance_variable(:@store) if defined?(@store)
      end

      def build_store(kind)
        case kind
        when "off" then nil
        when "memory" then ActiveSupport::Cache::MemoryStore.new(size: 32.megabytes)
        when "cache" then Rails.cache
        when nil then Rails.cache.is_a?(ActiveSupport::Cache::NullStore) ? build_store("memory") : Rails.cache
        else raise ArgumentError, "PUBLIC_API_RATE_LIMIT_STORE must be cache, memory or off, not #{kind.inspect}"
        end
      end
    end

    def initialize(store: self.class.store, now: Time.current)
      @store = store
      @now = now
    end

    def enabled? = !@store.nil?

    # Counts `units` against the caller's windows. Over either limit, the
    # units are given back and the result is not allowed.
    def charge(caller:, ip:, units:)
      minute, allowance = policies(caller)
      keys = window_keys(caller, ip, allowance)
      return Charge.new(keys:, units: 0, result: result(true, nil, minute, allowance, 0, 0)) unless enabled?

      minute_used = increment(keys[:minute], units, 2.minutes)
      allowance_used = allowance ? increment(keys[:allowance], units, allowance.name == "day" ? 2.days : 32.days) : 0
      code = if allowance && allowance_used > allowance.quota then "quota_exceeded"
      elsif minute_used > minute.quota then "rate_limited"
      end
      if code
        decrement(keys[:minute], units)
        decrement(keys[:allowance], units) if allowance
        return Charge.new(keys:, units: 0, result: result(false, code, minute, allowance, minute_used - units, allowance_used - units))
      end
      Charge.new(keys:, units:, result: result(true, nil, minute, allowance, minute_used, allowance_used))
    end

    # Gives back what a charge over-counted: `rate_units` toward the minute and
    # `units` toward the allowance are what the response really cost.
    def settle(charge, units:, rate_units: units)
      return charge.result unless enabled? && charge.units.positive?

      minute_refund = charge.units - rate_units
      allowance_refund = charge.units - units
      decrement(charge.keys[:minute], minute_refund) if minute_refund.positive?
      decrement(charge.keys[:allowance], allowance_refund) if allowance_refund.positive? && charge.keys[:allowance]
      r = charge.result
      r.with(minute_used: r.minute_used - [ minute_refund, 0 ].max, allowance_used: r.allowance_used - [ allowance_refund, 0 ].max)
    end

    # Units used in the caller's current allowance window (GET /v1/me).
    def allowance_used(caller:, ip:)
      _, allowance = policies(caller)
      return 0 unless allowance && enabled?

      @store.read(window_keys(caller, ip, allowance)[:allowance], raw: true).to_i
    end

    def policies(caller)
      plan = caller.plan
      minute = Policy.new(name: "minute", quota: plan.rate, seconds: 60)
      allowance = if plan.daily
        Policy.new(name: "day", quota: plan.daily, seconds: 86_400)
      elsif plan.monthly
        Policy.new(name: "month", quota: plan.monthly, seconds: MONTH_SECONDS)
      end
      [ minute, allowance ]
    end

    private

    def window_keys(caller, ip, allowance)
      utc = @now.utc
      rate_subject = caller.anonymous? ? "ip:#{ip}" : "key:#{caller.api_key&.id || "account:#{caller.account&.id}"}"
      allowance_subject = caller.anonymous? ? "ip:#{ip}" : "account:#{caller.account&.id}"
      keys = { minute: "public_api:rl:#{rate_subject}:m:#{@now.to_i / 60}" }
      if allowance
        period = allowance.name == "day" ? utc.strftime("%Y%m%d") : utc.strftime("%Y%m")
        keys[:allowance] = "public_api:rl:#{allowance_subject}:#{allowance.name}:#{period}"
      end
      keys
    end

    def increment(key, units, expires_in)
      @store.increment(key, units, expires_in:).to_i
    end

    def decrement(key, units)
      @store.decrement(key, units) if units.positive?
    end

    def result(allowed, code, minute, allowance, minute_used, allowance_used)
      Result.new(allowed:, code:, minute:, allowance:, minute_used:, allowance_used:, now: @now)
    end
  end
end
