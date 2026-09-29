require "test_helper"

# The MCP handshake and JSON-RPC behaviour of POST /mcp (MCP 2026-07-28 and
# the 2025-11-25 initialize handshake), on the official gem.
class McpProtocolTest < PublicApiTestCase
  TOOL_NAMES = %w[search_entities get_entity entity_spending search_spending describe_data].freeze

  setup { @key = key_with(%w[read:public usage:read]) }

  test "initialize negotiates 2025-11-25 and names the capabilities, the server and its instructions" do
    body = mcp_initialize(token: @key)
    assert_response :ok
    result = body["result"]
    assert_equal "2025-11-25", result["protocolVersion"]
    assert_equal({ "tools" => {}, "resources" => {}, "prompts" => {} }, result["capabilities"])
    assert_equal "buildcanada", result.dig("serverInfo", "name")
    assert_match(/never add them/, result["instructions"])
    assert_equal "0", response.headers["BC-Usage-Units"]
    assert_equal "mcp.initialize", response.headers["BC-Operation"]
    assert_nil response.headers["Mcp-Session-Id"], "stateless: no session"

    # A handshake can't negotiate the stateless 2026-07-28 lifecycle; it is counter-offered.
    assert_equal "2025-11-25", mcp_initialize(token: @key, version: "2026-07-28").dig("result", "protocolVersion")

    post "/mcp", params: { jsonrpc: "2.0", method: "notifications/initialized" }.to_json,
      headers: { "Content-Type" => "application/json", "Accept" => "application/json, text/event-stream", "Authorization" => "Bearer #{@key}" }
    assert_response :accepted
  end

  test "server/discover answers the 2026-07-28 lifecycle without a handshake" do
    body = mcp_request("server/discover", {}, token: @key)
    assert_response :ok
    assert_equal [ "2026-07-28" ], body.dig("result", "supportedVersions")
    assert_equal({ "tools" => {}, "resources" => {}, "prompts" => {} }, body.dig("result", "capabilities"))
  end

  test "tools/list: the five phase 1 tools, read-only, with input and output schemas" do
    %i[modern legacy].each do |era|
      tools = mcp_request("tools/list", {}, token: @key, era:).dig("result", "tools")
      assert_equal TOOL_NAMES, tools.map { |t| t["name"] }
      tools.each do |tool|
        assert_equal({ "readOnlyHint" => true, "destructiveHint" => false, "idempotentHint" => true, "openWorldHint" => false },
          tool["annotations"].slice("readOnlyHint", "destructiveHint", "idempotentHint", "openWorldHint"))
        assert_equal "object", tool.dig("inputSchema", "type")
        assert_equal "object", tool.dig("outputSchema", "type")
        assert tool.dig("outputSchema", "$defs", "ToolError"), "#{tool['name']} allows a tool error"
        assert_operator tool["description"].length, :>, 400, "#{tool['name']} explains when and how to use it"
        JSONSchemer.schema(tool["outputSchema"]) # a valid, self-contained document
      end
    end
    %w[entity_spending search_spending describe_data].each do |name|
      assert_match(/never add them/, mcp_request("tools/list", {}, token: @key).dig("result", "tools").find { |t| t["name"] == name }["description"])
    end
  end

  test "protocol errors are JSON-RPC errors; tool failures are tool results" do
    body = mcp_request("tools/call", { name: "no_such_tool", arguments: {} }, token: @key)
    assert_equal(-32602, body.dig("error", "code"))

    assert_equal(-32601, mcp_request("no/such_method", {}, token: @key).dig("error", "code"))

    mcp_post("{not json", token: @key, headers: { "MCP-Protocol-Version" => McpTestHelper::LEGACY })
    assert_equal(-32700, response.parsed_body.dig("error", "code"))

    # The 2026-07-28 header/body rules: Mcp-Method must match (-32020), versions must be supported (-32022).
    body = mcp_request("tools/list", {}, token: @key, headers: { "Mcp-Method" => "prompts/list" })
    assert_response :bad_request
    assert_equal(-32020, body.dig("error", "code"))
    mcp_post({ jsonrpc: "2.0", id: 1, method: "tools/list", params: { _meta: McpTestHelper::ENVELOPE.merge("io.modelcontextprotocol/protocolVersion" => "2099-01-01") } },
      token: @key, headers: { "MCP-Protocol-Version" => "2099-01-01", "Mcp-Method" => "tools/list" })
    assert_equal(-32022, response.parsed_body.dig("error", "code"))

    # Arguments the input schema refuses are a tool error the model can correct.
    result = call_tool("search_entities", { limit: 5 }, token: @key)
    assert result["isError"]
    assert_match(/query/, summary_text(result))
    result = call_tool("search_spending", { fiscal_year: "2024" }, token: @key)
    assert result["isError"]

    # And arguments the contract refuses are a structured invalid_parameter.
    error = assert_tool_error(call_tool("search_spending", { fiscal_year: "2024-26" }, token: @key), "invalid_parameter")
    assert_match(/fiscal_year/, error["detail"])
  end

  test "GET and DELETE are 405: the server is stateless" do
    get "/mcp", headers: { "Authorization" => "Bearer #{@key}" }
    assert_response :method_not_allowed
    assert_equal "POST", response.headers["Allow"]
    delete "/mcp", headers: { "Authorization" => "Bearer #{@key}" }
    assert_response :method_not_allowed
  end
end
