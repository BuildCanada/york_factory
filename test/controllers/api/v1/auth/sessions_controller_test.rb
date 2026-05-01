require "test_helper"

class Api::V1::Auth::SessionsControllerTest < ActionDispatch::IntegrationTest
  test "me returns user info for admin token" do
    token = Warden::JWTAuth::UserEncoder.new.call(users(:admin), :user, nil).first

    get api_v1_auth_me_url, headers: { "Authorization" => "Bearer #{token}" }
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal users(:admin).email, data["email"]
    assert_equal true, data["admin"]
  end

  test "me returns 403 for non-admin token" do
    token = Warden::JWTAuth::UserEncoder.new.call(users(:member), :user, nil).first

    get api_v1_auth_me_url, headers: { "Authorization" => "Bearer #{token}" }
    assert_response :forbidden
  end

  test "me returns 401 without token" do
    get api_v1_auth_me_url
    assert_response :unauthorized
  end

  test "me returns 401 for invalid token" do
    get api_v1_auth_me_url, headers: { "Authorization" => "Bearer garbage" }
    assert_response :unauthorized
  end
end
