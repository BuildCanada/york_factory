require "digest"

# Drives the MCP OAuth flow in integration tests (docs/public-interface-design.md §4.6).
# Integration requests go to http://www.example.com, which plays both the
# authorization server and the data host outside production.
module OauthTestHelper
  ORIGIN = "http://www.example.com".freeze
  MCP_RESOURCE = "#{ORIGIN}/mcp".freeze
  REST_RESOURCE = "#{ORIGIN}/v1".freeze
  REDIRECT_URI = "http://127.0.0.1:33418/callback".freeze

  Pkce = Data.define(:verifier, :challenge)

  def pkce_pair
    verifier = SecureRandom.urlsafe_base64(48)
    Pkce.new(verifier:, challenge: Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false))
  end

  def sign_in_user(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end

  def register_client(redirect_uris: [ REDIRECT_URI ], **metadata)
    post "/oauth/register", params: { client_name: "Test MCP Client", redirect_uris:, **metadata }.to_json,
      headers: { "Content-Type" => "application/json" }
    assert_response :created, response.body
    response.parsed_body
  end

  def authorize_params(client_id:, pkce:, resource: MCP_RESOURCE, scope: "read:public usage:read", redirect_uri: REDIRECT_URI, **extra)
    { client_id:, redirect_uri:, response_type: "code", state: "st4te", scope:, resource:,
      code_challenge: pkce.challenge, code_challenge_method: "S256", **extra }.compact
  end

  # Consents and returns the redirect's query parameters (code, state, iss).
  def authorize!(client_id:, pkce:, **)
    post "/oauth/authorize", params: authorize_params(client_id:, pkce:, **)
    assert_response :redirect, response.body
    redirect_query
  end

  def redirect_query = Rack::Utils.parse_query(URI.parse(response.location).query)

  def exchange_code!(client_id:, code:, pkce:, resource: MCP_RESOURCE)
    post "/oauth/token", params: { grant_type: "authorization_code", client_id:, code:, redirect_uri: REDIRECT_URI,
                                   code_verifier: pkce.verifier, resource: }.compact
    response.parsed_body
  end

  def refresh!(client_id:, refresh_token:, resource: MCP_RESOURCE)
    post "/oauth/token", params: { grant_type: "refresh_token", client_id:, refresh_token:, resource: }.compact
    response.parsed_body
  end

  # Registration, consent and code exchange in one: returns the token response.
  def oauth_tokens_for(user, resource: MCP_RESOURCE, scope: "read:public usage:read", **authorize_extra)
    client = register_client
    sign_in_user(user)
    pkce = pkce_pair
    query = authorize!(client_id: client["client_id"], pkce:, resource:, scope:, **authorize_extra)
    tokens = exchange_code!(client_id: client["client_id"], code: query["code"], pkce:, resource:)
    assert tokens["access_token"].present?, tokens.inspect
    tokens.merge("client_id" => client["client_id"])
  end

  def mcp_call(token)
    post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "tools/list" }.to_json,
      headers: { "Content-Type" => "application/json", "Authorization" => ("Bearer #{token}" if token) }.compact
  end
end

ActionDispatch::IntegrationTest.include(OauthTestHelper)
