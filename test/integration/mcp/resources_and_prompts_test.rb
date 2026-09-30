require "test_helper"

class McpResourcesAndPromptsTest < PublicApiTestCase
  setup { @key = key_with(%w[read:public usage:read]) }

  def read(uri, era: :modern) = mcp_request("resources/read", { uri: }, token: @key, era:)

  def contents(uri) = JSON.parse(read(uri).dig("result", "contents", 0, "text"))

  test "resources and templates are listed" do
    uris = mcp_request("resources/list", {}, token: @key).dig("result", "resources").map { |r| r["uri"] }
    assert_equal %w[buildcanada://releases/latest buildcanada://spending/sources buildcanada://datasets
                    buildcanada://guides/agent-rules buildcanada://guides/citing], uris
    templates = mcp_request("resources/templates/list", {}, token: @key, era: :legacy).dig("result", "resourceTemplates").map { |t| t["uriTemplate"] }
    assert_equal %w[buildcanada://entities/{id} buildcanada://dictionary/{term} buildcanada://datasets/{asset_key}
                    buildcanada://releases/{number} buildcanada://guides/{slug}], templates
    assert_equal "0", response.headers["BC-Usage-Units"]
  end

  test "resources read the /v1 operation they name, and cost its units" do
    release = contents("buildcanada://releases/latest")
    assert_equal 11, release.dig("data", "number")
    assert_equal "1", response.headers["BC-Usage-Units"]
    assert_equal "mcp.resources/read", response.headers["BC-Operation"]

    assert_equal "Town of Diamond Valley", contents("buildcanada://entities/#{DIAMOND_VALLEY}").dig("data", "name")
    assert_equal "fiscal_year", contents("buildcanada://dictionary/fiscal_year").dig("data", "term")
    assert_equal GRANTS, contents("buildcanada://datasets/#{ERB::Util.url_encode(GRANTS)}").dig("data", "asset_key")
    assert_includes contents("buildcanada://spending/sources")["data"].map { |s| s["source"] }, "proactive_grants"
    assert_equal 10, contents("buildcanada://releases/10").dig("data", "number")

    guide = read("buildcanada://guides/agent-rules", era: :legacy).dig("result", "contents", 0)
    assert_equal "text/markdown", guide["mimeType"]
    assert_match(/Never add amounts from different spending sources/, guide["text"])
  end

  test "an unknown resource is -32602; a problem is a JSON-RPC error carrying it" do
    %W[buildcanada://nope https://example.com buildcanada://entities/#{UNKNOWN} buildcanada://guides/nope].each do |uri|
      assert_equal(-32602, read(uri).dig("error", "code"), uri)
    end
    # A merged entity is a 301 problem on /v1, so a JSON-RPC error carrying it here.
    body = read("buildcanada://entities/#{DUP}")
    assert_equal(-32000, body.dig("error", "code"))
    assert_equal "redirected", body.dig("error", "data", "problem", "code")
  end

  test "prompts plan an investigation with the tools" do
    prompts = mcp_request("prompts/list", {}, token: @key).dig("result", "prompts")
    assert_equal %w[investigate_recipient follow_the_money], prompts.map { |p| p["name"] }
    body = mcp_request("prompts/get", { name: "investigate_recipient", arguments: { name: "Town of Diamond Valley" } }, token: @key)
    text = body.dig("result", "messages", 0, "content", "text")
    assert_match(/"Town of Diamond Valley"/, text)
    assert_match(/describe_data/, text)
    body = mcp_request("prompts/get", { name: "follow_the_money", arguments: { person_or_org: "Canadian Heritage" } }, token: @key, era: :legacy)
    assert_match(/role "payer"/, body.dig("result", "messages", 0, "content", "text"))
    assert_equal(-32602, mcp_request("prompts/get", { name: "investigate_recipient", arguments: {} }, token: @key).dig("error", "code"))
  end
end
