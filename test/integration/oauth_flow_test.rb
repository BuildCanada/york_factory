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

  test "GET /api/v1/me exposes the stable id only to identity-scoped tokens" do
    identity_app = Doorkeeper::Application.create!(
      name: "IdentityApp",
      redirect_uri: "https://example.com/callback",
      scopes: "public identity",
      confidential: true
    )
    token = Doorkeeper::AccessToken.create!(
      application: identity_app,
      scopes: "public identity",
      resource_owner_id: @member.id,
      expires_in: 7200
    )

    get api_v1_me_url, headers: { "Authorization" => "Bearer #{token.token}" }
    assert_response :success
    assert_equal @member.id.to_s, response.parsed_body["id"]
    assert_equal "member", response.parsed_body["role"]
  end

  test "an application registered without identity cannot obtain the id" do
    # Doorkeeper lets a blank-scope application request any configured scope,
    # so a TradingPost-style app can be issued an identity-scoped token.
    sign_in_as @member
    post oauth_authorization_url, params: {
      client_id: @trusted_app.uid,
      redirect_uri: @trusted_app.redirect_uri,
      response_type: "code",
      scope: "public identity"
    }
    code = URI.decode_www_form(URI.parse(response.location).query).to_h["code"]
    post oauth_token_url, params: {
      grant_type: "authorization_code",
      code: code,
      redirect_uri: @trusted_app.redirect_uri,
      client_id: @trusted_app.uid,
      client_secret: @trusted_app.secret
    }
    assert_response :success
    access = response.parsed_body["access_token"]

    get api_v1_me_url, headers: { "Authorization" => "Bearer #{access}" }
    assert_response :success
    assert_not response.parsed_body.key?("id"), "/me must not expose the id to an app not registered with identity"
  end

  test "an application registered with only public cannot request identity" do
    tradingpost = Doorkeeper::Application.create!(
      name: "TradingPostLike",
      redirect_uri: "https://example.com/callback",
      scopes: "public",
      confidential: true,
      trusted: true
    )
    sign_in_as @member
    post oauth_authorization_url, params: {
      client_id: tradingpost.uid,
      redirect_uri: tradingpost.redirect_uri,
      response_type: "code",
      scope: "public identity"
    }
    assert_no_match %r{[?&]code=}, response.location.to_s
  end

  # ---------------------------------------------------------------------------
  # Member app platform: identity scope + PKCE (S256)
  # ---------------------------------------------------------------------------

  test "identity scope and PKCE complete an authorization code flow" do
    member_apps = Doorkeeper::Application.create!(
      name: "Build Canada member apps",
      redirect_uri: "https://buildcanada.app/auth/york/callback",
      scopes: "public identity",
      confidential: true,
      trusted: true
    )
    verifier = SecureRandom.urlsafe_base64(32)
    challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)

    sign_in_as @admin
    post oauth_authorization_url, params: {
      client_id: member_apps.uid,
      redirect_uri: member_apps.redirect_uri,
      response_type: "code",
      scope: "public identity",
      state: "s1",
      code_challenge: challenge,
      code_challenge_method: "S256"
    }
    assert_response :redirect
    code = URI.decode_www_form(URI.parse(response.location).query).to_h["code"]
    assert_not_nil code

    token_params = {
      grant_type: "authorization_code",
      code: code,
      redirect_uri: member_apps.redirect_uri,
      client_id: member_apps.uid,
      client_secret: member_apps.secret
    }
    post oauth_token_url, params: token_params.merge(code_verifier: "wrong-#{verifier}")
    assert_response :bad_request

    # Doorkeeper revokes a grant on a failed exchange, so start a new one.
    post oauth_authorization_url, params: {
      client_id: member_apps.uid,
      redirect_uri: member_apps.redirect_uri,
      response_type: "code",
      scope: "public identity",
      state: "s2",
      code_challenge: challenge,
      code_challenge_method: "S256"
    }
    code = URI.decode_www_form(URI.parse(response.location).query).to_h["code"]
    post oauth_token_url, params: token_params.merge(code: code)
    assert_response :bad_request, "a PKCE grant must not exchange without its verifier"

    post oauth_authorization_url, params: {
      client_id: member_apps.uid,
      redirect_uri: member_apps.redirect_uri,
      response_type: "code",
      scope: "public identity",
      state: "s3",
      code_challenge: challenge,
      code_challenge_method: "S256"
    }
    code = URI.decode_www_form(URI.parse(response.location).query).to_h["code"]
    post oauth_token_url, params: token_params.merge(code: code, code_verifier: verifier)
    assert_response :success
    access = response.parsed_body["access_token"]
    assert_equal "public identity", response.parsed_body["scope"]

    get api_v1_me_url, headers: { "Authorization" => "Bearer #{access}" }
    assert_response :success
    assert_equal @admin.id.to_s, response.parsed_body["id"]
    assert_equal true, response.parsed_body["admin"]
  end

  test "plain PKCE challenges are refused" do
    sign_in_as @member
    post oauth_authorization_url, params: {
      client_id: @trusted_app.uid,
      redirect_uri: @trusted_app.redirect_uri,
      response_type: "code",
      code_challenge: "plain-challenge-value-plain-challenge-value-123",
      code_challenge_method: "plain"
    }
    assert_no_match %r{\?code=}, response.location.to_s
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

  test "post API returns draft content for an admin's token" do
    token = Doorkeeper::AccessToken.create!(
      application: @app,
      scopes: "public",
      resource_owner_id: @admin.id,
      expires_in: 7200
    )

    get api_v1_post_url(slug: posts(:draft_post).slug),
      headers: { "Authorization" => "Bearer #{token.token}" }
    assert_response :success
    assert_equal "draft-post", response.parsed_body["slug"]
  end

  test "post API returns 404 for draft without a preview token" do
    get api_v1_post_url(slug: posts(:draft_post).slug)
    assert_response :not_found
  end

  test "post API rejects a non-admin's token for preview" do
    token = Doorkeeper::AccessToken.create!(
      application: @app,
      scopes: "public",
      resource_owner_id: @member.id,
      expires_in: 7200
    )

    get api_v1_post_url(slug: posts(:draft_post).slug),
      headers: { "Authorization" => "Bearer #{token.token}" }
    assert_response :not_found
  end

  test "builder API returns draft content with published_at for an admin's token" do
    token = Doorkeeper::AccessToken.create!(
      application: @app,
      scopes: "public",
      resource_owner_id: @admin.id,
      expires_in: 7200
    )

    get api_v1_builder_url(slug: builders(:draft_builder).slug),
      headers: { "Authorization" => "Bearer #{token.token}" }
    assert_response :success
    assert_equal "draft-builder", response.parsed_body["slug"]
    assert response.parsed_body.key?("published_at")
    assert_nil response.parsed_body["published_at"]
  end

  test "builder API returns 404 for draft without a preview token" do
    get api_v1_builder_url(slug: builders(:draft_builder).slug)
    assert_response :not_found
  end

  test "builder API rejects a non-admin's token for preview" do
    token = Doorkeeper::AccessToken.create!(
      application: @app,
      scopes: "public",
      resource_owner_id: @member.id,
      expires_in: 7200
    )

    get api_v1_builder_url(slug: builders(:draft_builder).slug),
      headers: { "Authorization" => "Bearer #{token.token}" }
    assert_response :not_found
  end

  private

  def sign_in_as(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end
end
