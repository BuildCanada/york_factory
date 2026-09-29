require "test_helper"

# The MCP 2026-07-28 authorization flow end to end
# (docs/public-interface-design.md §4.6, WS-F): registration, authorization
# with PKCE, consent, token, refresh with rotation, and revocation.
class McpOauthFlowTest < ActionDispatch::IntegrationTest
  setup do
    @member = users(:member)
  end

  test "registration, PKCE authorization, consent, token, refresh and revocation" do
    # 1. Unauthenticated MCP request: 401 pointing at the resource metadata.
    mcp_call(nil)
    assert_response :unauthorized
    assert_equal %(Bearer scope="read:public usage:read", resource_metadata="#{ORIGIN}/.well-known/oauth-protected-resource/mcp"),
      response.headers["WWW-Authenticate"]

    # 2. Dynamic client registration.
    client = register_client
    client_id = client["client_id"]
    assert_equal "none", client["token_endpoint_auth_method"]
    assert_nil client["client_secret"]
    app = Doorkeeper::Application.find_by!(uid: client_id)
    assert app.dynamic?
    assert_not app.confidential?

    # 3. The consent screen names the client, where it redirects and what it can do.
    sign_in_user(@member)
    pkce = pkce_pair
    get "/oauth/authorize", params: authorize_params(client_id:, pkce:)
    assert_response :success
    assert_match "Connect Test MCP Client to Build Canada", response.body
    assert_match "127.0.0.1", response.body
    assert_match "sends you back to your own computer", response.body
    assert_includes response.body, CGI.escapeHTML(Oauth::Settings::SCOPE_DESCRIPTIONS["read:public"])
    assert_includes response.body, CGI.escapeHTML(Oauth::Settings::SCOPE_DESCRIPTIONS["usage:read"])

    # 4. Consent: a code, the state and the issuer (RFC 9207) come back.
    query = authorize!(client_id:, pkce:)
    assert query["code"].present?
    assert_equal "st4te", query["state"]
    assert_equal ORIGIN, query["iss"]
    assert response.location.start_with?(REDIRECT_URI)
    grant = Doorkeeper::AccessGrant.by_token(query["code"])
    assert_equal MCP_RESOURCE, grant.resource
    assert_equal Account.personal_for!(@member).id, grant.account_id
    assert_equal "S256", grant.code_challenge_method
    assert AuditEvent.exists?(action: "oauth.authorized", subject: app, account_id: grant.account_id)

    # 5. Token: needs the verifier; bound to the resource; one hour.
    tokens = exchange_code!(client_id:, code: query["code"], pkce:)
    assert_response :success
    assert_equal "Bearer", tokens["token_type"]
    assert_equal 3600, tokens["expires_in"]
    assert_equal "read:public usage:read", tokens["scope"]
    assert tokens["refresh_token"].present?
    access = Doorkeeper::AccessToken.by_token(tokens["access_token"])
    assert_equal MCP_RESOURCE, access.resource
    assert_equal grant.account_id, access.account_id

    # 6. The token works on /mcp.
    mcp_call(tokens["access_token"])
    assert_response :success
    assert_equal "2.0", response.parsed_body["jsonrpc"]

    # 7. Refresh rotates: a new pair, and the old refresh token is dead at once.
    refreshed = refresh!(client_id:, refresh_token: tokens["refresh_token"])
    assert_response :success
    assert_not_equal tokens["refresh_token"], refreshed["refresh_token"]
    assert_equal 3600, refreshed["expires_in"]
    assert access.reload.revoked?
    new_access = Doorkeeper::AccessToken.by_token(refreshed["access_token"])
    assert_equal MCP_RESOURCE, new_access.resource
    assert_equal access.account_id, new_access.account_id

    # 8. Reusing the old refresh token is refused and revokes the whole authorization.
    refresh!(client_id:, refresh_token: tokens["refresh_token"])
    assert_response :bad_request
    assert_equal "invalid_grant", response.parsed_body["error"]
    assert new_access.reload.revoked?
    assert AuditEvent.exists?(action: "oauth.refresh_token_reused", subject: app)
    mcp_call(refreshed["access_token"])
    assert_response :unauthorized
    assert_match 'error="invalid_token"', response.headers["WWW-Authenticate"]

    # 9. A fresh authorization, then RFC 7009 revocation by the public client.
    query = authorize!(client_id:, pkce: (pkce = pkce_pair))
    tokens = exchange_code!(client_id:, code: query["code"], pkce:)
    post "/oauth/revoke", params: { client_id:, token: tokens["refresh_token"], token_type_hint: "refresh_token" }
    assert_response :success
    mcp_call(tokens["access_token"])
    assert_response :unauthorized
    assert AuditEvent.exists?(action: "oauth.token_revoked", subject: app, actor_kind: "client")
  end

  test "an authorization code can be redeemed only once" do
    client = register_client
    sign_in_user(@member)
    pkce = pkce_pair
    query = authorize!(client_id: client["client_id"], pkce:)
    exchange_code!(client_id: client["client_id"], code: query["code"], pkce:)
    assert_response :success

    exchange_code!(client_id: client["client_id"], code: query["code"], pkce:)
    assert_response :bad_request
    assert_equal "invalid_grant", response.parsed_body["error"]
  end

  test "PKCE is required, S256 only, and the verifier must match" do
    client = register_client
    sign_in_user(@member)
    pkce = pkce_pair

    # No challenge: refused, back at the client.
    post "/oauth/authorize", params: authorize_params(client_id: client["client_id"], pkce:).except(:code_challenge, :code_challenge_method)
    assert_equal "invalid_request", redirect_query["error"]
    assert_not Doorkeeper::AccessGrant.exists?

    # plain is refused.
    post "/oauth/authorize", params: authorize_params(client_id: client["client_id"], pkce:, code_challenge: pkce.verifier, code_challenge_method: "plain")
    assert_equal "invalid_request", redirect_query["error"]
    assert_not Doorkeeper::AccessGrant.exists?

    # A challenge without a method means plain (RFC 7636 §4.3), so it is refused too.
    post "/oauth/authorize", params: authorize_params(client_id: client["client_id"], pkce:).except(:code_challenge_method)
    assert_equal "invalid_request", redirect_query["error"]
    assert_not Doorkeeper::AccessGrant.exists?

    # S256 with the wrong verifier.
    query = authorize!(client_id: client["client_id"], pkce:)
    post "/oauth/token", params: { grant_type: "authorization_code", client_id: client["client_id"], code: query["code"],
                                   redirect_uri: REDIRECT_URI, code_verifier: pkce_pair.verifier, resource: MCP_RESOURCE }
    assert_response :bad_request
    assert_equal "invalid_grant", response.parsed_body["error"]
  end

  test "the resource indicator is required and must be one of ours" do
    client = register_client
    sign_in_user(@member)

    post "/oauth/authorize", params: authorize_params(client_id: client["client_id"], pkce: pkce_pair, resource: nil)
    assert_response :redirect
    assert_equal "invalid_target", redirect_query["error"]
    assert_equal ORIGIN, redirect_query["iss"]
    assert_equal "st4te", redirect_query["state"]

    post "/oauth/authorize", params: authorize_params(client_id: client["client_id"], pkce: pkce_pair, resource: "https://evil.example/mcp")
    assert_equal "invalid_target", redirect_query["error"]
    assert_not Doorkeeper::AccessGrant.exists?

    # Case and a trailing slash are normalized (MCP "Canonical Server URI").
    query = authorize!(client_id: client["client_id"], pkce: pkce_pair, resource: "HTTP://WWW.EXAMPLE.COM/mcp/")
    assert_equal MCP_RESOURCE, Doorkeeper::AccessGrant.by_token(query["code"]).resource
  end

  test "a token request naming a different resource than the grant is refused" do
    client = register_client
    sign_in_user(@member)
    pkce = pkce_pair
    query = authorize!(client_id: client["client_id"], pkce:)

    tokens = exchange_code!(client_id: client["client_id"], code: query["code"], pkce:, resource: REST_RESOURCE)
    assert_response :bad_request
    assert_equal "invalid_target", tokens["error"]

    tokens = exchange_code!(client_id: client["client_id"], code: query["code"], pkce:)
    assert_response :success
    refresh!(client_id: client["client_id"], refresh_token: tokens["refresh_token"], resource: REST_RESOURCE)
    assert_response :bad_request
    assert_equal "invalid_target", response.parsed_body["error"]
  end

  test "tokens are audience-bound: an MCP token is refused by the REST API and the CMS" do
    tokens = oauth_tokens_for(@member)

    with_rest_probe do
      get "/probe", headers: { "Authorization" => "Bearer #{tokens['access_token']}" }
      assert_response :unauthorized
      assert_equal "Access token not for this resource", response.parsed_body["title"]
      assert_equal %(Bearer error="invalid_token", error_description="Access token not for this resource", resource_metadata="#{ORIGIN}/.well-known/oauth-protected-resource/v1"),
        response.headers["WWW-Authenticate"]
    end

    # The CMS refuses it (it lacks the first-party `public` scope, and has a resource).
    get api_v1_me_url, headers: { "Authorization" => "Bearer #{tokens['access_token']}" }
    assert_includes [ 401, 403 ], response.status

    rest = oauth_tokens_for(@member, resource: REST_RESOURCE)
    with_rest_probe do
      get "/probe", headers: { "Authorization" => "Bearer #{rest['access_token']}" }
      assert_response :success
      assert_equal "oauth", response.parsed_body["kind"]
    end
    mcp_call(rest["access_token"])
    assert_response :unauthorized
  end

  test "a first-party (TradingPost) token is not accepted by /mcp" do
    app = Doorkeeper::Application.create!(name: "TradingPost", redirect_uri: "https://example.com/callback", confidential: true)
    token = Doorkeeper::AccessToken.create!(application: app, resource_owner_id: @member.id, scopes: "read:public", expires_in: 3600)

    mcp_call(token.token)
    assert_response :unauthorized
    assert_match 'error="invalid_token"', response.headers["WWW-Authenticate"]
  end

  test "read:persons is granted only when the account accepted the data terms" do
    scope = "read:public read:persons usage:read"
    tokens = oauth_tokens_for(@member, scope:)
    assert_equal "read:public usage:read", tokens["scope"]

    account = Account.personal_for!(@member)
    account.update!(terms_accepted_at: Time.current)
    get "/oauth/authorize", params: authorize_params(client_id: tokens["client_id"], pkce: pkce_pair, scope:)
    assert_match Oauth::Settings::PERSONS_NOTE, response.body
    pkce = pkce_pair
    query = authorize!(client_id: tokens["client_id"], pkce:, scope:)
    granted = exchange_code!(client_id: tokens["client_id"], code: query["code"], pkce:)
    assert_equal "read:persons read:public usage:read", granted["scope"].split.sort.join(" ")
  end

  test "usage is billed to an organization account the user manages, chosen at consent" do
    org = Account.create!(name: "Newsroom", kind: "organization", plan: "partner")
    org.memberships.create!(user: @member, role: "admin")
    stranger = Account.create!(name: "Someone else", kind: "organization", plan: "free")

    client = register_client
    sign_in_user(@member)
    get "/oauth/authorize", params: authorize_params(client_id: client["client_id"], pkce: pkce_pair)
    assert_match "Newsroom", response.body
    assert_no_match "Someone else", response.body

    pkce = pkce_pair
    query = authorize!(client_id: client["client_id"], pkce:, account_id: org.id)
    assert_equal org.id, Doorkeeper::AccessGrant.by_token(query["code"]).account_id

    # An account the user doesn't belong to falls back to their personal account.
    query = authorize!(client_id: client["client_id"], pkce: pkce_pair, account_id: stranger.id)
    assert_equal Account.personal_for!(@member).id, Doorkeeper::AccessGrant.by_token(query["code"]).account_id
  end

  test "redirect URIs must match exactly" do
    client = register_client
    sign_in_user(@member)

    get "/oauth/authorize", params: authorize_params(client_id: client["client_id"], pkce: pkce_pair, redirect_uri: "#{REDIRECT_URI}?extra=1")
    assert_response :bad_request
    assert_includes response.body, CGI.escapeHTML("doesn't exactly match")

    # A loopback IP may use any port (RFC 8252 §7.3).
    get "/oauth/authorize", params: authorize_params(client_id: client["client_id"], pkce: pkce_pair, redirect_uri: "http://127.0.0.1:5555/callback")
    assert_response :success
  end

  test "a disabled client can't be authorized and its tokens stop working" do
    tokens = oauth_tokens_for(@member)
    app = Doorkeeper::Application.find_by!(uid: tokens["client_id"])
    app.update!(disabled_at: Time.current)

    mcp_call(tokens["access_token"])
    assert_response :unauthorized

    get "/oauth/authorize", params: authorize_params(client_id: app.uid, pkce: pkce_pair)
    assert_response :unauthorized
  end

  test "a refresh token unused for 30 days no longer works" do
    tokens = oauth_tokens_for(@member)
    Doorkeeper::AccessToken.by_refresh_token(tokens["refresh_token"]).update_columns(created_at: 31.days.ago)

    refresh!(client_id: tokens["client_id"], refresh_token: tokens["refresh_token"])
    assert_response :bad_request
    assert_equal "invalid_grant", response.parsed_body["error"]
  end

  test "an expired access token is a 401 with an invalid_token challenge" do
    tokens = oauth_tokens_for(@member)
    Doorkeeper::AccessToken.by_token(tokens["access_token"]).update_columns(created_at: 2.hours.ago)

    mcp_call(tokens["access_token"])
    assert_response :unauthorized
    assert_equal "Access token expired", response.parsed_body["title"]
  end

  test "a suspended account's tokens are refused" do
    tokens = oauth_tokens_for(@member)
    Account.personal_for!(@member).update!(suspended_at: Time.current, suspended_reason: "abuse")

    mcp_call(tokens["access_token"])
    assert_response :forbidden
    assert_equal "account_suspended", response.parsed_body["code"]
  end

  test "API keys also work on /mcp" do
    issued = issue_key(user: @member, scopes: %w[read:public])
    mcp_call(issued.raw_key)
    assert_response :success
  end

  test "TradingPost's flow is unchanged: no resource, two-hour tokens, CMS access" do
    app = Doorkeeper::Application.create!(name: "TradingPost", redirect_uri: "https://example.com/callback", confidential: true)
    sign_in_user(@member)
    post "/oauth/authorize", params: { client_id: app.uid, redirect_uri: app.redirect_uri, response_type: "code", resource: MCP_RESOURCE }
    query = redirect_query
    assert_equal ORIGIN, query["iss"]
    assert_nil Doorkeeper::AccessGrant.by_token(query["code"]).resource

    post "/oauth/token", params: { grant_type: "authorization_code", code: query["code"], redirect_uri: app.redirect_uri,
                                   client_id: app.uid, client_secret: app.secret }
    assert_response :success
    assert_equal 7200, response.parsed_body["expires_in"]
    get api_v1_me_url, headers: { "Authorization" => "Bearer #{response.parsed_body['access_token']}" }
    assert_response :success
  end

  private

  class RestProbeController < ActionController::API
    include PublicApiAuthentication

    before_action -> { authenticate_public_api!(scopes: [ "read:public" ]) }

    def show = render(json: { kind: current_api_caller.kind, account_id: current_api_caller.account&.id })
  end

  def with_rest_probe(&)
    with_routing do |set|
      set.draw do
        get "/probe", to: "mcp_oauth_flow_test/rest_probe#show"
      end
      yield
    end
  end
end
