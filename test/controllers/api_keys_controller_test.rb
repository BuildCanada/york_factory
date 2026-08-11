require "test_helper"

class ApiKeysControllerTest < ActionDispatch::IntegrationTest
  setup { post user_session_path, params: { email: users(:admin).email, password: "password123" } }

  test "signed in user can create a key and sees its secret once" do
    assert_difference "users(:admin).api_keys.count", 1 do
      post profile_api_keys_path, params: { api_key: { name: "Toronto memo agent" } }
    end

    assert_response :created
    assert_select ".api-key-secret", text: /yfu_/

    get profile_api_keys_path
    assert_response :success
    assert_select ".api-key-secret", count: 0
  end

  test "user can only revoke their own key" do
    other_key, = ApiKey.issue!(user: users(:member), name: "member key")

    delete profile_api_key_path(other_key)

    assert_response :not_found
    assert_nil other_key.reload.revoked_at
  end

  test "unauthenticated user is redirected to login" do
    delete destroy_user_session_path
    get profile_api_keys_path
    assert_redirected_to new_user_session_path
  end
end
