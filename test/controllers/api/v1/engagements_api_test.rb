require "test_helper"

# Endorse/critique endpoints are now authenticated by a Doorkeeper access token
# (the same token TradingPost obtains via the OAuth flow), and attribute the
# engagement to the token's resource owner.
class EngagementsApiTest < ActionDispatch::IntegrationTest
  setup do
    @memo = memos(:published_memo)
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

  # --- endorsements ----------------------------------------------------------

  test "endorsing requires a token" do
    post api_v1_memo_endorsements_url(@memo)
    assert_response :unauthorized
  end

  test "a member with a postal code can endorse" do
    assert_difference -> { @memo.reload.endorsements_count }, 1 do
      post api_v1_memo_endorsements_url(@memo), headers: auth(users(:member))
    end
    assert_response :created
    assert_equal users(:member).name, response.parsed_body["name"]
  end

  test "a user without a postal code is told to provide one" do
    post api_v1_memo_endorsements_url(@memo), headers: auth(users(:superadmin))
    assert_response :unprocessable_entity
    assert_equal "postal_code_required", response.parsed_body["error"]
  end

  test "a second endorsement by the same user conflicts" do
    post api_v1_memo_endorsements_url(@memo), headers: auth(users(:member))
    assert_response :created
    post api_v1_memo_endorsements_url(@memo), headers: auth(users(:member))
    assert_response :conflict
    assert_equal "already_submitted", response.parsed_body["error"]
  end

  test "endorsement index is public" do
    Endorsement.create!(memo: @memo, user: users(:member))
    get api_v1_memo_endorsements_url(@memo)
    assert_response :success
    assert_equal 1, response.parsed_body["data"].size
    assert_equal users(:member).name, response.parsed_body["data"].first["name"]
  end

  # --- critiques -------------------------------------------------------------

  test "critiquing requires a token" do
    post api_v1_memo_critiques_url(@memo), params: { body: "x" }
    assert_response :unauthorized
  end

  test "a member can submit a critique that starts pending" do
    post api_v1_memo_critiques_url(@memo),
      params: { body: "The fiscal section needs more detail." }, headers: auth(users(:member))
    assert_response :created
    assert_equal "pending", response.parsed_body["status"]
  end

  test "critique without a body is rejected" do
    post api_v1_memo_critiques_url(@memo), params: { body: "" }, headers: auth(users(:member))
    assert_response :unprocessable_entity
  end

  test "critique index only exposes approved critiques" do
    approved = Critique.create!(memo: @memo, user: users(:member), body: "Approved one.")
    approved.approve!(users(:admin))
    Critique.create!(memo: @memo, user: users(:regular), body: "Still pending.")

    get api_v1_memo_critiques_url(@memo)
    assert_response :success
    assert_equal 1, response.parsed_body["data"].size
  end
end
