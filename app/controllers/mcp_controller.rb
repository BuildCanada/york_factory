# POST /mcp: the Build Canada MCP server (docs/public-interface-design.md
# §7.1, WS-G), MCP 2026-07-28 over the Streamable HTTP transport, stateless
# and in JSON response mode. The official `mcp` gem speaks the protocol;
# Mcp::Server builds the server for this request, and the tools answer from
# the /v1 controllers in process (Mcp::Api), so MCP and REST agree.
#
# Every request needs an API key or an OAuth access token issued for this
# resource (Keys::Authenticate, through PublicApiAuthentication). Without
# one it gets a 401 whose WWW-Authenticate names the RFC 9728 metadata:
# MCP clients start the OAuth flow only on a 401, so anonymous access (which
# the REST API allows) would stop them ever asking the user to sign in.
#
# Units: each tool call or resource read costs the /v1 operations it runs,
# charged to the same limiter as REST (Mcp::Meter); protocol messages
# (initialize, discovery, lists, prompts) are free. The response says what it
# cost in BC-Usage-Units and BC-Operation (mcp.<tool>), for the edge Worker.
class McpController < ActionController::API
  include PublicApiAuthentication

  # GET would open an SSE stream and DELETE end a session; a stateless server
  # has neither (Streamable HTTP lets it answer 405).
  ALLOW = "POST".freeze

  before_action :require_edge
  before_action -> { authenticate_public_api!(scopes: [ "read:public" ], resource: :mcp, anonymous: false) }

  def create
    request_id = PublicApi::RequestId.generate
    meter = Mcp::Meter.new(caller: current_api_caller, ip: request.remote_ip, limit: !edge_verified?)
    context = Mcp::Context.new(caller: current_api_caller, api: Mcp::Api.new(caller: current_api_caller, request:, meter:), meter:,
      locale: request.headers["Accept-Language"].to_s.downcase.start_with?("fr") ? "fr" : "en", request_id:)
    transport = MCP::Server::Transports::StreamableHTTPTransport.new(
      Mcp::Server.build(context), stateless: true, enable_json_response: true, serve_subscriptions_listen: false,
      # Host and Origin are not a defence here: every request carries a bearer
      # credential (no cookies), and the route is bound to the data host.
      dns_rebinding_protection: false
    )
    status, headers, body = transport.handle_request(request)
    headers.each { |name, value| response.headers[name] = value }
    response.headers.merge!(meter.headers)
    response.headers["BC-Operation"] = operation_name
    response.headers["BC-Request-Id"] = request_id.to_s
    text = +""
    body.each { |chunk| text << chunk.to_s }
    body.close if body.respond_to?(:close)
    render body: text, status:, content_type: headers["Content-Type"] || "application/json"
  end

  def method_not_allowed
    response.headers["Allow"] = ALLOW
    render json: { jsonrpc: "2.0", id: nil, error: { code: -32000, message: "Method not allowed. This server is stateless: send JSON-RPC with POST." } },
      status: :method_not_allowed
  end

  private

  # mcp.<tool> for a tool call, mcp.<method> otherwise (§5.5, BC-Operation).
  def operation_name
    body = JSON.parse(request.raw_post)
    return "mcp" unless body.is_a?(Hash)

    body["method"] == "tools/call" ? "mcp.#{body.dig('params', 'name')}" : "mcp.#{body['method']}"
  rescue JSON::ParserError
    "mcp"
  end

  # In production the data-edge Worker fronts /mcp and signs what it forwards
  # (§2, "Origin protection"), as for /v1: PUBLIC_API_REQUIRE_EDGE=true
  # refuses anything else. A signed request is limited by the Worker, not here.
  def require_edge
    return if edge_verified? || !ActiveModel::Type::Boolean.new.cast(ENV.fetch("PUBLIC_API_REQUIRE_EDGE", "false"))

    render_api_problem(status: 401, code: "unauthenticated", title: "Authentication required", detail: "Call the MCP server at https://data.buildcanada.com/mcp.")
  end

  def edge_verified?
    return @edge_verified if defined?(@edge_verified)

    @edge_verified = Edge::Signature.valid?(
      method: request.request_method, path: request.fullpath, body: request.raw_post,
      timestamp: request.headers[Edge::Signature::TIMESTAMP_HEADER], signature: request.headers[Edge::Signature::SIGNATURE_HEADER]
    )
  end
end
