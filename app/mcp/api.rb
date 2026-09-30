module Mcp
  # Calls a /v1 operation in process, as the caller the MCP request
  # authenticated, and returns its status and parsed body. This is how the
  # MCP tools reuse the REST API: the same controllers, query objects and
  # serializers answer both, so a tool's structuredContent is exactly what
  # GET /v1/... returns, provenance, cite and caveats included, and can't
  # drift from it (docs/public-interface-design.md §5.3 and §7.1).
  #
  # The request goes straight to the router (no middleware, no network). It
  # carries the authenticated Keys::Caller in the Rack env
  # (PublicApiAuthentication::INTERNAL_CALLER_ENV), so the controller skips
  # its own authentication, edge check and rate limit; Mcp::Meter charges the
  # units instead.
  #
  #   response = api.get("/v1/search", q: "Diamond Valley", limit: 10)
  #   response.ok?     # => true
  #   response.body    # => { "data" => [...], "meta" => {...}, "links" => {...} }
  #   response.units   # => 3
  class Api
    Response = Data.define(:status, :body, :headers, :units, :path) do
      def ok? = status == 200

      def redirect? = status == 301

      def problem? = status >= 400

      def location = headers["Location"] || headers["location"]
    end

    def initialize(caller:, request:, meter:)
      @caller = caller
      @request = request
      @meter = meter
    end

    # `params` values may be arrays (sent comma-separated) or nil (left out).
    # `operation` names the contract operation, for the units estimate.
    def get(path, operation:, **params)
      query = params.compact.transform_values { |v| v.is_a?(Array) ? v.join(",") : v.to_s }
      url = PublicApi::Links.url(path, query.transform_keys(&:to_s))
      op = PublicApi::Spec.operation(operation)
      estimate = op.units_for(limit: query["limit"]&.to_i, count_exact: query["count"] == "exact")
      @meter.charge(operation, estimate) do
        response = dispatch(url)
        [ response, response.units ]
      end
    end

    private

    def dispatch(url)
      env = Rails.application.env_config.merge(Rack::MockRequest.env_for(url, method: "GET", **forwarded_headers))
      env[PublicApiAuthentication::INTERNAL_CALLER_ENV] = @caller
      status, headers, body = Rails.application.routes.call(env)
      text = +""
      body.each { |chunk| text << chunk }
      body.close if body.respond_to?(:close)
      parsed = text.empty? ? nil : JSON.parse(text)
      Response.new(status:, body: parsed, headers: headers.to_h, units: headers["BC-Usage-Units"].to_i, path: url)
    end

    def forwarded_headers
      {
        "HTTP_HOST" => @request.host_with_port,
        "HTTPS" => @request.ssl? ? "on" : "off",
        "REMOTE_ADDR" => @request.remote_ip,
        "HTTP_ACCEPT_LANGUAGE" => @request.headers["Accept-Language"],
        "HTTP_ACCEPT" => "application/json"
      }.compact
    end
  end
end
