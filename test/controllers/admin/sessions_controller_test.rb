require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  # Login page
  test "login page renders" do
    get new_user_session_path
    assert_response :success
  end

  test "login page redirects when already authenticated as admin" do
    post user_session_path, params: { email: users(:admin).email, password: "password123" }
    get new_user_session_path
    assert_redirected_to admin_root_path
  end

  test "login page redirects when already authenticated as member" do
    post user_session_path, params: { email: users(:member).email, password: "password123" }
    get new_user_session_path
    assert_redirected_to profile_path
  end

  # Successful login
  test "login with admin credentials redirects to admin dashboard" do
    post user_session_path, params: { email: users(:admin).email, password: "password123" }
    assert_redirected_to admin_root_path
    follow_redirect!
    assert_response :success
  end

  test "login with member credentials redirects to profile" do
    post user_session_path, params: { email: users(:member).email, password: "password123" }
    assert_redirected_to profile_path
  end

  test "login with superadmin credentials redirects to admin dashboard" do
    post user_session_path, params: { email: users(:superadmin).email, password: "password123" }
    assert_redirected_to admin_root_path
  end

  # Failed login
  test "login with wrong password renders login with 422" do
    post user_session_path, params: { email: users(:admin).email, password: "wrong" }
    assert_response :unprocessable_entity
  end

  test "login with non-existent email renders login with 422" do
    post user_session_path, params: { email: "nobody@example.com", password: "password123" }
    assert_response :unprocessable_entity
  end

  # Logout
  test "logout via DELETE clears session and redirects to login" do
    post user_session_path, params: { email: users(:admin).email, password: "password123" }
    delete destroy_user_session_path
    assert_redirected_to new_user_session_path

    get admin_root_path
    assert_redirected_to new_user_session_path
  end

  test "logout via form POST with _method=delete clears session" do
    post user_session_path, params: { email: users(:admin).email, password: "password123" }
    get admin_root_path
    assert_response :success

    post destroy_user_session_path, params: { _method: "delete" }
    assert_redirected_to new_user_session_path

    get admin_root_path
    assert_redirected_to new_user_session_path
  end

  # Auth guard
  test "unauthenticated access to admin redirects to login" do
    get admin_root_path
    assert_redirected_to new_user_session_path
  end
end
