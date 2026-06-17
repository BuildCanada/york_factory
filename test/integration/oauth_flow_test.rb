require "test_helper"

class OauthFlowTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:admin)
    @member = users(:member)

    @app = Doorkeeper::Application.create!(
      name: "TestApp",
      redirect_uri: "https://example.com/callback",
      scopes: "admin",
      confidential: true,
      trusted: false
    )

    @trusted_app = Doorkeeper::Application.create!(
      name: "TrustedApp",
      redirect_uri: "https://example.com/callback",
      scopes: "admin",
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
      response_type: "code",
      scope: "admin"
    )
    assert_redirected_to new_user_session_url
  end

  test "GET /oauth/authorize redirects non-admin users to login" do
    sign_in_as @member
    get oauth_authorization_url(
      client_id: @app.uid,
      redirect_uri: @app.redirect_uri,
      response_type: "code",
      scope: "admin"
    )
    assert_redirected_to new_user_session_url
  end

  test "GET /oauth/authorize shows authorization form for admin user" do
    sign_in_as @admin
    get oauth_authorization_url(
      client_id: @app.uid,
      redirect_uri: @app.redirect_uri,
      response_type: "code",
      scope: "admin"
    )
    assert_response :success
    assert_match @app.name, response.body
  end

  test "GET /oauth/authorize auto-authorizes trusted apps without showing form" do
    sign_in_as @admin
    post oauth_authorization_url,
      params: {
        client_id: @trusted_app.uid,
        redirect_uri: @trusted_app.redirect_uri,
        response_type: "code",
        scope: "admin"
      }
    assert_response :redirect
    assert_match %r{https://example\.com/callback\?code=}, response.location
  end

  # ---------------------------------------------------------------------------
  # Full authorization code flow
  # ---------------------------------------------------------------------------

  test "POST /oauth/authorize issues authorization code for admin" do
    sign_in_as @admin
    post oauth_authorization_url,
      params: {
        client_id: @app.uid,
        redirect_uri: @app.redirect_uri,
        response_type: "code",
        scope: "admin"
      }
    assert_response :redirect
    assert_match %r{https://example\.com/callback\?code=}, response.location
  end

  test "POST /oauth/token exchanges code for access token with admin scope" do
    sign_in_as @admin
    post oauth_authorization_url,
      params: {
        client_id: @app.uid,
        redirect_uri: @app.redirect_uri,
        response_type: "code",
        scope: "admin"
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
    assert_equal "admin", json["scope"]
    assert json["refresh_token"].present?
    assert json["expires_in"].present?
  end

  # ---------------------------------------------------------------------------
  # Token revocation
  # ---------------------------------------------------------------------------

  test "POST /oauth/revoke revokes an active access token" do
    token = Doorkeeper::AccessToken.create!(
      application: @app,
      resource_owner_id: @admin.id,
      scopes: "admin",
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
  # Preview mode via Doorkeeper token
  # ---------------------------------------------------------------------------

  test "memo API returns draft content when Doorkeeper admin token is present" do
    token = Doorkeeper::AccessToken.create!(
      application: @app,
      resource_owner_id: @admin.id,
      scopes: "admin",
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
      resource_owner_id: @admin.id,
      scopes: "admin",
      expires_in: 7200
    )
    token.revoke

    get api_v1_memo_url(memos(:draft_memo)),
      headers: { "Authorization" => "Bearer #{token.token}" }
    assert_response :not_found
  end

  test "memo API rejects Doorkeeper token without admin scope for preview" do
    no_scope_app = Doorkeeper::Application.create!(
      name: "NoScopeApp",
      redirect_uri: "https://example.com/cb",
      scopes: "",
      confidential: true,
      trusted: false
    )
    token = Doorkeeper::AccessToken.create!(
      application: no_scope_app,
      resource_owner_id: @member.id,
      scopes: "",
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
