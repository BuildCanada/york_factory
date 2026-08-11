require "test_helper"

class MeApiTest < ActionDispatch::IntegrationTest
  setup do
    @oauth_app = Doorkeeper::Application.create!(
      name: "TP", redirect_uri: "https://example.com/cb", scopes: "", confidential: true, trusted: true
    )
  end

  def auth(user)
    token = Doorkeeper::AccessToken.create!(
      application: @oauth_app, scopes: "public", resource_owner_id: user.id, expires_in: 7200
    )
    { "Authorization" => "Bearer #{token.token}" }
  end

  test "GET /me exposes postal_code and engagement_ready" do
    get "/api/v1/me", headers: auth(users(:member))
    assert_response :success
    json = response.parsed_body
    assert_equal users(:member).postal_code, json["postal_code"]
    assert_equal true, json["engagement_ready"]
  end

  test "GET /me reports engagement_ready false without a postal code" do
    get "/api/v1/me", headers: auth(users(:superadmin))
    assert_response :success
    assert_equal false, response.parsed_body["engagement_ready"]
  end

  test "PATCH /me sets a postal code and normalizes it" do
    user = users(:superadmin) # starts with no postal code
    patch "/api/v1/me", params: { user: { postal_code: "k1a0a6" } }, headers: auth(user)
    assert_response :success
    assert_equal "K1A 0A6", response.parsed_body["postal_code"]
    assert_equal true, response.parsed_body["engagement_ready"]
    assert_equal "K1A 0A6", user.reload.postal_code
  end

  test "PATCH /me rejects an invalid postal code" do
    patch "/api/v1/me", params: { user: { postal_code: "99999" } }, headers: auth(users(:member))
    assert_response :unprocessable_entity
  end

  test "PATCH /me requires a token" do
    patch "/api/v1/me", params: { user: { postal_code: "K1A 0A6" } }
    assert_response :unauthorized
  end

  test "user API key is accepted anywhere OAuth authentication is accepted" do
    _, raw = ApiKey.issue!(user: users(:member), name: "me endpoint")

    get "/api/v1/me", headers: { "Authorization" => "Bearer #{raw}" }

    assert_response :success
    assert_equal users(:member).email, response.parsed_body["email"]
  end
end
