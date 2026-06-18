require "test_helper"

class OauthFlowTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:admin)
    @member = users(:member)

    @app = Doorkeeper::Application.create!(
      name: "TestApp",
      redirect_uri: "https://example.com/callback",
      scopes: "",
      confidential: true,
      trusted: false
    )

    @trusted_app = Doorkeeper::Application.create!(
      name: "TrustedApp",
      redirect_uri: "https://example.com/callback",
      scopes: "",
      confidential: true,
      trusted: true
    )
  end

  # ---------------------------------------------------------------------------
  # Authorization endpoint
  # ---------------------------------------------------------------------------

  test "GET /oauth/authorize redirects unauthenticated users to login" do
    get oauth_authorization_url(
      client_id: @app.uid,
      redirect_uri: @app.redirect_uri,
      response_type: "code"
    )
    assert_redirected_to new_user_session_url
  end

  test "GET /oauth/authorize shows authorization form for any signed-in user" do
    sign_in_as @member
    get oauth_authorization_url(
      client_id: @app.uid,
      redirect_uri: @app.redirect_uri,
      response_type: "code"
    )
    assert_response :success
    assert_match @app.name, response.body
  end

  test "GET /oauth/authorize auto-authorizes trusted apps without showing form" do
    sign_in_as @member
    post oauth_authorization_url,
      params: {
        client_id: @trusted_app.uid,
        redirect_uri: @trusted_app.redirect_uri,
        response_type: "code"
      }
    assert_response :redirect
    assert_match %r{https://example\.com/callback\?code=}, response.location
  end

  # ---------------------------------------------------------------------------
  # Full authorization code flow
  # ---------------------------------------------------------------------------

  test "POST /oauth/authorize issues authorization code for any signed-in user" do
    sign_in_as @member
    post oauth_authorization_url,
      params: {
        client_id: @app.uid,
        redirect_uri: @app.redirect_uri,
        response_type: "code"
      }
    assert_response :redirect
    assert_match %r{https://example\.com/callback\?code=}, response.location
  end

  test "POST /oauth/token exchanges code for an access token" do
    sign_in_as @member
    post oauth_authorization_url,
      params: {
        client_id: @app.uid,
        redirect_uri: @app.redirect_uri,
        response_type: "code"
      }

    code = URI.decode_www_form(URI.parse(response.location).query).to_h["code"]
    assert_not_nil code

    post oauth_token_url,
      params: {
        grant_type: "authorization_code",
        code: code,
        redirect_uri: @app.redirect_uri,
        client_id: @app.uid,
        client_secret: @app.secret
      }

    assert_response :success
    json = response.parsed_body
    assert json["access_token"].present?
    assert json["refresh_token"].present?
    assert json["expires_in"].present?
  end

  # ---------------------------------------------------------------------------
  # Refresh token grant (silent session renewal — TradingPost middleware)
  # ---------------------------------------------------------------------------

  test "POST /oauth/token renews an access token via the refresh_token grant" do
    sign_in_as @admin
    post oauth_authorization_url,
      params: {
        client_id: @app.uid,
        redirect_uri: @app.redirect_uri,
        response_type: "code"
      }
    code = URI.decode_www_form(URI.parse(response.location).query).to_h["code"]

    post oauth_token_url,
      params: {
        grant_type: "authorization_code",
        code: code,
        redirect_uri: @app.redirect_uri,
        client_id: @app.uid,
        client_secret: @app.secret
      }
    original = response.parsed_body
    refresh_token = original["refresh_token"]
    assert refresh_token.present?

    # Exchange the refresh token for a fresh access token, as the middleware does
    # once the short-lived access token has expired.
    post oauth_token_url,
      params: {
        grant_type: "refresh_token",
        refresh_token: refresh_token,
        client_id: @app.uid,
        client_secret: @app.secret
      }
    assert_response :success
    refreshed = response.parsed_body
    assert refreshed["access_token"].present?
    assert refreshed["refresh_token"].present?
    assert_not_equal original["access_token"], refreshed["access_token"]

    # The renewed access token authorizes a request…
    get api_v1_me_url, headers: { "Authorization" => "Bearer #{refreshed['access_token']}" }
    assert_response :success
    assert_equal @admin.email, response.parsed_body["email"]

    # …and the superseded access token is revoked.
    get api_v1_me_url, headers: { "Authorization" => "Bearer #{original['access_token']}" }
    assert_response :unauthorized
  end

  test "POST /oauth/token rejects an invalid refresh token" do
    post oauth_token_url,
      params: {
        grant_type: "refresh_token",
        refresh_token: "not-a-real-refresh-token",
        client_id: @app.uid,
        client_secret: @app.secret
      }
    assert_response :bad_request
    assert_equal "invalid_grant", response.parsed_body["error"]
  end

  # ---------------------------------------------------------------------------
  # Token revocation
  # ---------------------------------------------------------------------------

  test "POST /oauth/revoke revokes an active access token" do
    token = Doorkeeper::AccessToken.create!(
      application: @app,
      scopes: "public",
      resource_owner_id: @admin.id,
      expires_in: 7200
    )

    post oauth_revoke_url,
      params: {
        token: token.token,
        client_id: @app.uid,
        client_secret: @app.secret
      }

    assert_response :success
    assert token.reload.revoked?
  end

  # ---------------------------------------------------------------------------
  # Userinfo endpoint
  # ---------------------------------------------------------------------------

  test "GET /api/v1/me returns admin: true for an admin's token" do
    token = Doorkeeper::AccessToken.create!(
      application: @app,
      scopes: "public",
      resource_owner_id: @admin.id,
      expires_in: 7200
    )

    get api_v1_me_url, headers: { "Authorization" => "Bearer #{token.token}" }
    assert_response :success
    json = response.parsed_body
    assert_equal @admin.email, json["email"]
    assert_equal true, json["admin"]
    assert_not json.key?("id"), "/me must not expose the internal user id"
  end

  test "GET /api/v1/me returns admin: false for a non-admin's token" do
    token = Doorkeeper::AccessToken.create!(
      application: @app,
      scopes: "public",
      resource_owner_id: @member.id,
      expires_in: 7200
    )

    get api_v1_me_url, headers: { "Authorization" => "Bearer #{token.token}" }
    assert_response :success
    assert_equal false, response.parsed_body["admin"]
  end

  test "GET /api/v1/me rejects requests without a token" do
    get api_v1_me_url
    assert_response :unauthorized
  end

  # ---------------------------------------------------------------------------
  # Preview mode via Doorkeeper token (gated on real admin status)
  # ---------------------------------------------------------------------------

  test "memo API returns draft content for an admin's token" do
    token = Doorkeeper::AccessToken.create!(
      application: @app,
      scopes: "public",
      resource_owner_id: @admin.id,
      expires_in: 7200
    )

    get api_v1_memo_url(memos(:draft_memo)),
      headers: { "Authorization" => "Bearer #{token.token}" }
    assert_response :success
    assert_equal "draft-memo", response.parsed_body["slug"]
  end

  test "memo API returns 404 for draft without a preview token" do
    get api_v1_memo_url(memos(:draft_memo))
    assert_response :not_found
  end

  test "memo API rejects revoked Doorkeeper token for preview" do
    token = Doorkeeper::AccessToken.create!(
      application: @app,
      scopes: "public",
      resource_owner_id: @admin.id,
      expires_in: 7200
    )
    token.revoke

    get api_v1_memo_url(memos(:draft_memo)),
      headers: { "Authorization" => "Bearer #{token.token}" }
    assert_response :not_found
  end

  test "memo API rejects a non-admin's token for preview" do
    token = Doorkeeper::AccessToken.create!(
      application: @app,
      scopes: "public",
      resource_owner_id: @member.id,
      expires_in: 7200
    )

    get api_v1_memo_url(memos(:draft_memo)),
      headers: { "Authorization" => "Bearer #{token.token}" }
    assert_response :not_found
  end

  private

  def sign_in_as(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end
end
