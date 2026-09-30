module Mcp
  # Request units for one POST /mcp, counted with the same limiter and the
  # same weights as /v1 (docs/public-interface-design.md §6.1: "an MCP tool
  # call costs the units of the endpoint it wraps"). Each /v1 operation a
  # tool or resource runs is charged its x-bc-units before it runs and
  # settled to what it really cost (BC-Usage-Units) afterwards, exactly as a
  # REST request is, so a tool call costs the sum of the operations it wraps.
  #
  # Nothing is limited here when the data-edge Worker signed the request (it
  # limits and meters itself) or when the limiter is off; units are still
  # counted, for the BC-Usage-Units header the Worker settles from.
  class Meter
    class Refused < StandardError
      attr_reader :problem

      def initialize(problem)
        @problem = problem
        super(problem.detail)
      end
    end

    attr_reader :units, :operations, :result

    def initialize(caller:, ip:, limit: true, limiter: PublicApi::RateLimiter.new)
      @caller = caller
      @ip = ip
      @limiter = limit && limiter.enabled? ? limiter : nil
      @units = 0
      @operations = []
    end

    # Runs the block as one charged operation of `estimate` units. The block
    # returns [value, actual units]. Raises Refused over the caller's limits.
    def charge(operation_id, estimate)
      charge = @limiter&.charge(caller: @caller, ip: @ip, units: estimate)
      if charge && !charge.result.allowed
        @result = charge.result
        raise Refused, PublicApi::Problem.rate_limited(charge.result, caller: @caller)
      end

      begin
        value, actual = yield
      rescue StandardError
        # It raised before it could say what it cost: an error, 1 unit.
        settle(charge, 1)
        raise
      end
      settle(charge, actual)
      @operations << operation_id
      value
    end

    # A tool call that ran no /v1 operation still costs 1 unit (a call that
    # failed its own checks costs what a failed REST request does).
    def minimum!(units = 1)
      return unless @units.zero? && @operations.empty?

      charge("mcp", units) { [ nil, units ] }
    rescue Refused
      nil
    end

    def headers
      headers = @result ? @result.headers : {}
      headers = headers.merge("Retry-After" => @result.retry_after.to_s) if @result && !@result.allowed
      headers.merge("BC-Usage-Units" => @units.to_s)
    end

    private

    def settle(charge, actual)
      actual = actual.to_i
      @result = @limiter.settle(charge, units: actual) if charge
      @units += actual
    end
  end
end
