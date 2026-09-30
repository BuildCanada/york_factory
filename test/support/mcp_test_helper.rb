require "json_schemer"

# Drives /mcp in integration tests, over both lifecycles the server speaks:
# :modern (MCP 2026-07-28: the _meta envelope and the Mcp-Method/Mcp-Name
# headers on every request, no handshake) and :legacy (the 2025-11-25
# initialize handshake, then plain requests).
module McpTestHelper
  MODERN = "2026-07-28".freeze
  LEGACY = "2025-11-25".freeze
  ENVELOPE = { "io.modelcontextprotocol/protocolVersion" => MODERN, "io.modelcontextprotocol/clientCapabilities" => {},
               "io.modelcontextprotocol/clientInfo" => { "name" => "york-factory-test", "version" => "1" } }.freeze

  def mcp_post(payload, token:, headers: {})
    headers = { "Content-Type" => "application/json", "Accept" => "application/json, text/event-stream" }.merge(headers)
    headers["Authorization"] = "Bearer #{token}" if token
    post("/mcp", params: payload.is_a?(String) ? payload : payload.to_json, headers:)
    response.body.present? && response.media_type == "application/json" ? response.parsed_body : nil
  end

  # One JSON-RPC request; returns the parsed response.
  def mcp_request(method, params = {}, token:, era: :modern, id: 1, headers: {})
    params = params.dup
    if era == :modern
      params[:_meta] = ENVELOPE
      headers = { "MCP-Protocol-Version" => MODERN, "Mcp-Method" => method }.merge(headers)
      headers["Mcp-Name"] = params[:name] || params[:uri] if %w[tools/call prompts/get resources/read].include?(method)
    else
      headers = { "MCP-Protocol-Version" => LEGACY }.merge(headers)
    end
    mcp_post({ jsonrpc: "2.0", id:, method:, params: }, token:, headers:)
  end

  def mcp_initialize(token:, version: LEGACY)
    mcp_post({ jsonrpc: "2.0", id: 0, method: "initialize",
               params: { protocolVersion: version, capabilities: {}, clientInfo: { name: "york-factory-test", version: "1" } } }, token:)
  end

  # tools/call: the result, after checking it against the tool's outputSchema
  # (success and error results alike: clients validate both).
  def call_tool(name, arguments = {}, token:, era: :modern)
    body = mcp_request("tools/call", { name:, arguments: }, token:, era:)
    assert_response :ok
    assert body.key?("result"), "expected a result, got #{body.inspect.first(500)}"
    result = body["result"]
    assert_output_conforms(name, result["structuredContent"]) if result.key?("structuredContent")
    result
  end

  def assert_output_conforms(name, structured)
    tool = Mcp::Server::TOOLS.find { |t| t.name_value == name }
    schema = JSON.parse(tool.to_h[:outputSchema].to_json)
    errors = JSONSchemer.schema(schema).validate(structured).first(5).map { |e| "#{e['data_pointer']}: #{e['error']}" }
    assert_empty errors, "#{name} structuredContent does not match its outputSchema"
  end

  def assert_tool_error(result, code)
    assert result["isError"], "expected a tool error, got #{result.inspect.first(400)}"
    assert_equal code, result.dig("structuredContent", "error", "code"), result.inspect.first(400)
    result["structuredContent"]["error"]
  end

  def summary_text(result) = result["content"].first["text"]
end

ActionDispatch::IntegrationTest.include(McpTestHelper)
