require "test_helper"

# Who may call /mcp, which tool needs which scope, the privacy rules, and
# units: API keys and OAuth tokens through Keys::Authenticate, a 401
# challenge for everyone else, per-tool scopes as structured tool errors, and
# the /v1 limiter charging each tool call the units of what it wraps.
class McpAuthAndLimitsTest < PublicApiTestCase
  def issued = @issued ||= issue_key(user: users(:member), scopes: %w[read:public usage:read])

  def key = issued.raw_key

  # ---------- authentication ----------

  test "without credentials: 401 with a challenge naming the resource metadata" do
    body = mcp_request("tools/list", {}, token: nil)
    assert_response :unauthorized
    assert_nil body
    assert_equal %(Bearer scope="read:public usage:read", resource_metadata="http://www.example.com/.well-known/oauth-protected-resource/mcp"),
      response.headers["WWW-Authenticate"]
    assert_equal "unauthenticated", response.parsed_body["code"]
  end

  test "a mistyped or revoked key is 401 invalid_token" do
    mcp_request("tools/list", {}, token: mistyped(key))
    assert_response :unauthorized
    assert_match(/error="invalid_token"/, response.headers["WWW-Authenticate"])

    Keys::Revoke.call(api_key: issued.api_key, reason: "user", context: system_context)
    mcp_request("tools/list", {}, token: key)
    assert_response :unauthorized
    assert_equal "API key revoked", response.parsed_body["title"]
  end

  test "a key without read:public is 403 insufficient_scope" do
    mcp_request("tools/list", {}, token: key_with(%w[usage:read]))
    assert_response :forbidden
    assert_match(/error="insufficient_scope", scope="read:public"/, response.headers["WWW-Authenticate"])
  end

  test "an OAuth token issued for /mcp works; one issued for /v1 does not" do
    tokens = oauth_tokens_for(users(:member))
    result = call_tool("search_entities", { query: "Canadian Heritage" }, token: tokens["access_token"])
    assert_equal "gid://buildcanada/Entity/#{HERITAGE}", result.dig("structuredContent", "data", 0, "entity", "id")
    assert_equal "3", response.headers["BC-Usage-Units"]

    rest = oauth_tokens_for(users(:member), resource: OauthTestHelper::REST_RESOURCE)
    mcp_request("tools/list", {}, token: rest["access_token"])
    assert_response :unauthorized
    assert_equal "Access token not for this resource", response.parsed_body["title"]
  end

  # ---------- scopes and privacy ----------

  test "a person needs read:persons: a structured insufficient_scope, then the person with the scope" do
    error = assert_tool_error(call_tool("get_entity", { id: PERSON }, token: key), "insufficient_scope")
    assert_equal "read:persons", error["required_scope"]
    assert_equal 403, error["status"]
    error = assert_tool_error(call_tool("search_entities", { query: "Jane Example", class: "person" }, token: key, era: :legacy), "insufficient_scope")
    assert_equal "read:persons", error["required_scope"]
    # Without the scope a person is simply not found by name.
    assert_empty call_tool("search_entities", { query: "Jane Q. Example" }, token: key).dig("structuredContent", "data")

    result = call_tool("get_entity", { id: PERSON }, token: persons_key)
    refute result["isError"]
    assert_equal "person", result.dig("structuredContent", "entity", "data", "entity_class")
    # Persons are found by name only, never by identifier (§3.7).
    assert_empty call_tool("search_entities", { query: "999999999" }, token: persons_key).dig("structuredContent", "data")
  end

  test "an OAuth token carries its scopes: read:persons comes by consent and data terms" do
    Account.personal_for!(users(:member)).update!(terms_accepted_at: Time.current)
    tokens = oauth_tokens_for(users(:member), scope: "read:public read:persons")
    refute call_tool("get_entity", { id: PERSON }, token: tokens["access_token"])["isError"]
  end

  test "a tool that declares a scope refuses callers without it, before doing anything" do
    tool = Class.new(Mcp::Tools::GetEntity) do
      tool_name "persons_probe"
      required_scopes "read:persons"
    end
    caller = Keys::Caller.for(issued.api_key)
    meter = Mcp::Meter.new(caller:, ip: "203.0.113.1")
    api = Minitest::Mock.new # never called
    context = Mcp::Context.new(caller:, api:, meter:, locale: "en", request_id: "req_test")
    response = tool.call(server_context: { mcp: context }, id: PERSON).to_h
    assert response[:isError]
    assert_equal({ "code" => "insufficient_scope", "required_scope" => "read:persons" },
      response.dig(:structuredContent, :error).slice("code", "required_scope"))
    assert_equal 1, meter.units
  end

  test "no street address and no full postal code of an individual leaves through a tool" do
    result = call_tool("search_spending", { query: "Artist residency" }, token: key)
    record = result.dig("structuredContent", "data").find { |r| r["id"].end_with?(G_PERSON) }
    assert_equal "T2P", record["recipient_postal_code"]
    refute_includes result["content"].map { |c| c["text"] }.join, "T2P 1J9"

    result = call_tool("get_entity", { id: DIAMOND_VALLEY, include: %w[relationships] }, token: key)
    text = result["content"].map { |c| c["text"] }.join
    refute_includes text, "mailing_address"
    refute_includes text, "Box 1, Diamond Valley"
    refute_includes text, "never served"
    # (call_tool also checks every key of structuredContent: nothing named address or street.)
  end

  # ---------- units and limits ----------

  test "protocol messages cost nothing; each tool call costs the units of what it wraps" do
    mcp_request("tools/list", {}, token: key)
    assert_equal [ "0", "mcp.tools/list" ], [ response.headers["BC-Usage-Units"], response.headers["BC-Operation"] ]
    assert_nil response.headers["RateLimit"]

    call_tool("search_entities", { query: "Diamond Valley" }, token: key)
    assert_match(/\A"minute";r=117;t=\d+\z/, response.headers["RateLimit"])
    assert_equal "99997", response.headers["BC-Quota-Remaining"]
    call_tool("entity_spending", { id: DIAMOND_VALLEY }, token: key)
    assert_equal "99993", response.headers["BC-Quota-Remaining"]
    # The limiter is the REST limiter: /v1 sees the same window.
    api_get "/v1/entities", key: key
    assert_equal "99992", response.headers["BC-Quota-Remaining"]
  end

  test "over the rate, a tool call is a structured rate_limited error that costs nothing" do
    PublicApi::RateLimiter.new.charge(caller: Keys::Caller.for(issued.api_key), ip: "127.0.0.1", units: 119)
    error = assert_tool_error(call_tool("search_entities", { query: "Diamond Valley" }, token: key), "rate_limited")
    assert_operator error["retry_after_seconds"], :>, 0
    assert_equal "0", response.headers["BC-Usage-Units"]
    assert_equal error["retry_after_seconds"].to_s, response.headers["Retry-After"]
    assert_match(/Retry in \d+ seconds/, summary_text(call_tool("search_entities", { query: "Diamond Valley" }, token: key)))
    # A 1-unit call still fits.
    refute call_tool("get_entity", { id: HERITAGE }, token: key)["isError"]
  end

  test "a request the edge Worker signed is not limited here, but still reports its units" do
    body = { jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: "search_entities", arguments: { query: "Diamond Valley" } } }.to_json
    signed = Edge::Signature.headers(method: "POST", path: "/mcp", body:, secret: "edge-test-secret")
    Edge.stub(:secret, "edge-test-secret") do
      mcp_post(body, token: key, headers: signed.merge("MCP-Protocol-Version" => McpTestHelper::LEGACY))
    end
    assert_response :ok
    assert_equal "3", response.headers["BC-Usage-Units"]
    assert_nil response.headers["RateLimit"]
  end

  test "PUBLIC_API_REQUIRE_EDGE refuses unsigned requests" do
    with_env("PUBLIC_API_REQUIRE_EDGE" => "true") do
      mcp_request("tools/list", {}, token: key)
      assert_response :unauthorized
    end
  end
end
