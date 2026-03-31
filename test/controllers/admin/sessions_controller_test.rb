require "test_helper"

class Admin::SessionsControllerTest < ActionDispatch::IntegrationTest
  # Login page
  test "login page renders" do
    get admin_login_path
    assert_response :success
  end

  test "login page redirects to dashboard when already authenticated" do
    post admin_login_path, params: { email: users(:admin).email, password: "password123" }
    get admin_login_path
    assert_redirected_to admin_root_path
  end

  # Successful login
  test "login with valid admin credentials redirects to dashboard" do
    post admin_login_path, params: { email: users(:admin).email, password: "password123" }
    assert_redirected_to admin_root_path
    follow_redirect!
    assert_response :success
  end

  # Failed login
  test "login with wrong password renders login with 422" do
    post admin_login_path, params: { email: users(:admin).email, password: "wrong" }
    assert_response :unprocessable_entity
  end

  test "login with non-existent email renders login with 422" do
    post admin_login_path, params: { email: "nobody@example.com", password: "password123" }
    assert_response :unprocessable_entity
  end

  test "login with non-admin user renders login with 422" do
    post admin_login_path, params: { email: users(:regular).email, password: "password123" }
    assert_response :unprocessable_entity
  end

  # Logout
  test "logout via GET clears session and redirects to login" do
    post admin_login_path, params: { email: users(:admin).email, password: "password123" }
    get admin_logout_path
    assert_redirected_to admin_login_path

    # Verify session is cleared
    get admin_root_path
    assert_redirected_to admin_login_path
  end

  test "logout via DELETE clears session and redirects to login" do
    post admin_login_path, params: { email: users(:admin).email, password: "password123" }
    delete admin_logout_path
    assert_redirected_to admin_login_path

    get admin_root_path
    assert_redirected_to admin_login_path
  end

  # Auth guard
  test "unauthenticated access to admin redirects to login" do
    get admin_root_path
    assert_redirected_to admin_login_path
  end
end
