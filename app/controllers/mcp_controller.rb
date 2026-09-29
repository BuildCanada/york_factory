# POST /mcp — authentication only, until WS-G's MCP server replaces this
# action (docs/public-interface-design.md §7.1). It exists so MCP clients can
# run the OAuth flow end to end: without credentials it answers 401 with a
# WWW-Authenticate challenge naming the RFC 9728 metadata; with an API key
# or an OAuth token issued for this resource it answers a JSON-RPC error.
#
# Anonymous callers are refused here (unlike the REST API): MCP clients start
# the OAuth flow only on a 401, so an anonymous 200 would stop Claude and MCP
# Inspector from ever asking the user to sign in. WS-G decides whether to
# keep that.
class McpController < ActionController::API
  include PublicApiAuthentication

  before_action -> { authenticate_public_api!(scopes: [ "read:public" ], resource: :mcp, anonymous: false) }

  def create
    render json: { jsonrpc: "2.0", id: rpc_id, error: { code: -32601, message: "The Build Canada MCP server isn't live yet." } }
  end

  private

  def rpc_id
    body = JSON.parse(request.raw_post)
    body["id"] if body.is_a?(Hash)
  rescue JSON::ParserError
    nil
  end
end
