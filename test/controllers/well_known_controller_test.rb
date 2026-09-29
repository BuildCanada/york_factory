require "test_helper"

# RFC 9728 and RFC 8414 discovery documents (docs/public-interface-design.md §4.6).
class WellKnownControllerTest < ActionDispatch::IntegrationTest
  test "protected resource metadata for the MCP server, at the root and path-inserted" do
    [ "/.well-known/oauth-protected-resource", "/.well-known/oauth-protected-resource/mcp" ].each do |path|
      get path
      assert_response :success
      body = response.parsed_body
      assert_equal "http://www.example.com/mcp", body["resource"]
      assert_equal [ "http://www.example.com" ], body["authorization_servers"]
      assert_equal %w[read:public read:persons usage:read], body["scopes_supported"]
      assert_equal %w[header], body["bearer_methods_supported"]
      assert_match "public", response.headers["Cache-Control"]
    end
  end

  test "protected resource metadata for the REST API" do
    get "/.well-known/oauth-protected-resource/v1"
    assert_response :success
    assert_equal "http://www.example.com/v1", response.parsed_body["resource"]
  end

  test "an unknown resource path is not found" do
    get "/.well-known/oauth-protected-resource/admin"
    assert_response :not_found
  end

  test "authorization server metadata advertises PKCE S256, CIMD, DCR and iss" do
    get "/.well-known/oauth-authorization-server"
    assert_response :success
    body = response.parsed_body
    assert_equal "http://www.example.com", body["issuer"]
    assert_equal "http://www.example.com/oauth/authorize", body["authorization_endpoint"]
    assert_equal "http://www.example.com/oauth/token", body["token_endpoint"]
    assert_equal "http://www.example.com/oauth/register", body["registration_endpoint"]
    assert_equal "http://www.example.com/oauth/revoke", body["revocation_endpoint"]
    assert_equal %w[S256], body["code_challenge_methods_supported"]
    assert_equal %w[code], body["response_types_supported"]
    assert_equal %w[authorization_code refresh_token], body["grant_types_supported"]
    assert_includes body["token_endpoint_auth_methods_supported"], "none"
    assert body["client_id_metadata_document_supported"]
    assert body["authorization_response_iss_parameter_supported"]
    assert_not_includes body["scopes_supported"], "offline_access"
  end

  test "production URLs come from the configured hosts" do
    ENV["OAUTH_ISSUER"] = "https://auth.buildcanada.com"
    ENV["PUBLIC_DATA_ORIGIN"] = "https://data.buildcanada.com"
    get "/.well-known/oauth-protected-resource"
    assert_equal "https://data.buildcanada.com/mcp", response.parsed_body["resource"]
    assert_equal [ "https://auth.buildcanada.com" ], response.parsed_body["authorization_servers"]
    get "/.well-known/oauth-authorization-server"
    assert_equal "https://auth.buildcanada.com", response.parsed_body["issuer"]
  ensure
    ENV.delete("OAUTH_ISSUER")
    ENV.delete("PUBLIC_DATA_ORIGIN")
  end

  test "browser-based MCP clients can read the metadata and see the /mcp challenge (CORS)" do
    get "/.well-known/oauth-authorization-server", headers: { "Origin" => "http://localhost:6274" }
    assert_equal "*", response.headers["Access-Control-Allow-Origin"]

    post "/mcp", headers: { "Origin" => "http://localhost:6274" }
    assert_response :unauthorized
    assert_equal "*", response.headers["Access-Control-Allow-Origin"]
    assert_match "WWW-Authenticate", response.headers["Access-Control-Expose-Headers"]
  end
end
