require "test_helper"

class ProfileControllerTest < ActionDispatch::IntegrationTest
  # Auth guard
  test "unauthenticated access redirects to login" do
    get profile_path
    assert_redirected_to new_user_session_path
  end

  # Member login
  test "member can log in and access profile" do
    post user_session_path, params: { email: users(:member).email, password: "password123" }
    get profile_path
    assert_response :success
  end

  test "admin can access profile" do
    post user_session_path, params: { email: users(:admin).email, password: "password123" }
    get profile_path
    assert_response :success
  end

  test "invalid credentials show error" do
    post user_session_path, params: { email: users(:member).email, password: "wrong" }
    assert_response :unprocessable_entity
  end

  # Show
  test "show renders profile form" do
    post user_session_path, params: { email: users(:member).email, password: "password123" }
    get profile_path
    assert_response :success
    assert_select "form"
  end

  # Update
  test "update changes profile fields" do
    post user_session_path, params: { email: users(:member).email, password: "password123" }
    patch profile_path, params: { user: { name: "New Name", postal_code: "V5K 0A1" } }
    assert_redirected_to profile_path

    user = users(:member).reload
    assert_equal "New Name", user.name
    assert_equal "V5K 0A1", user.postal_code
  end

  test "update with blank password keeps existing password" do
    post user_session_path, params: { email: users(:member).email, password: "password123" }
    original_password = users(:member).encrypted_password
    patch profile_path, params: { user: { name: "Same Pass", password: "" } }
    assert_redirected_to profile_path
    assert_equal original_password, users(:member).reload.encrypted_password
  end

  test "update address fields" do
    post user_session_path, params: { email: users(:member).email, password: "password123" }
    patch profile_path, params: { user: {
      address_line1: "456 Oak Ave", address_line2: "Unit 2", city: "Vancouver", province: "BC"
    } }
    assert_redirected_to profile_path

    user = users(:member).reload
    assert_equal "456 Oak Ave", user.address_line1
    assert_equal "Unit 2", user.address_line2
    assert_equal "Vancouver", user.city
    assert_equal "BC", user.province
  end

  test "update with duplicate email re-renders form" do
    post user_session_path, params: { email: users(:member).email, password: "password123" }
    patch profile_path, params: { user: { email: users(:admin).email } }
    assert_response :unprocessable_entity
  end

  test "member cannot change their own role" do
    post user_session_path, params: { email: users(:member).email, password: "password123" }
    patch profile_path, params: { user: { role: "admin" } }
    assert users(:member).reload.member?
  end

  # Logout
  test "logout clears session" do
    post user_session_path, params: { email: users(:member).email, password: "password123" }
    delete destroy_user_session_path
    assert_redirected_to new_user_session_path

    get profile_path
    assert_redirected_to new_user_session_path
  end

  # Members cannot access admin
  test "member cannot access admin panel" do
    post user_session_path, params: { email: users(:member).email, password: "password123" }
    get admin_root_path
    assert_response :redirect
  end
end
