require "test_helper"

class Admin::UsersControllerTest < ActionDispatch::IntegrationTest
  setup do
    post user_session_path, params: { email: users(:admin).email, password: "password123" }
  end

  # Auth guard
  test "unauthenticated access redirects to login" do
    delete destroy_user_session_path
    get admin_users_path
    assert_redirected_to new_user_session_path
  end

  test "member cannot access admin" do
    delete destroy_user_session_path
    post user_session_path, params: { email: users(:member).email, password: "password123" }
    get admin_users_path
    assert_response :redirect
  end

  # Index
  test "index lists users including current admin" do
    get admin_users_path
    assert_response :success
    assert_select "table tbody tr"
  end

  test "index shows current user with you label" do
    get admin_users_path
    assert_response :success
    assert_select "td", /\(you\)/
  end

  test "index filters users by search query" do
    get admin_users_path, params: { q: "member@example" }
    assert_response :success
    assert_select "table tbody tr", 1
  end

  # New
  test "new renders form" do
    get new_admin_user_path
    assert_response :success
    assert_select "form"
  end

  # Create
  test "create adds a new admin user" do
    assert_difference "User.count", 1 do
      post admin_users_path, params: { user: { name: "New Admin", email: "new@buildcanada.com", password: "securepass", role: "admin" } }
    end
    assert_redirected_to admin_users_path

    user = User.find_by(email: "new@buildcanada.com")
    assert user.admin?
  end

  test "create adds a member user" do
    assert_difference "User.count", 1 do
      post admin_users_path, params: { user: { name: "New Member", email: "newmember@example.com", password: "securepass", role: "member", postal_code: "K1A 0A6" } }
    end
    assert_redirected_to admin_users_path

    user = User.find_by(email: "newmember@example.com")
    assert user.member?
    assert_equal "K1A 0A6", user.postal_code
  end

  test "create member without required fields fails" do
    assert_no_difference "User.count" do
      post admin_users_path, params: { user: { email: "incomplete@example.com", password: "securepass", role: "member" } }
    end
    assert_response :unprocessable_entity
  end

  test "create admin without name and postal_code succeeds" do
    assert_difference "User.count", 1 do
      post admin_users_path, params: { user: { email: "noadmin@buildcanada.com", password: "securepass", role: "admin" } }
    end
    assert_redirected_to admin_users_path
  end

  test "create with invalid data re-renders form" do
    assert_no_difference "User.count" do
      post admin_users_path, params: { user: { name: "No Email", email: "", password: "securepass", role: "admin" } }
    end
    assert_response :unprocessable_entity
  end

  test "create with duplicate email re-renders form" do
    assert_no_difference "User.count" do
      post admin_users_path, params: { user: { name: "Dup", email: users(:admin).email, password: "securepass", role: "admin" } }
    end
    assert_response :unprocessable_entity
  end

  # Edit
  test "edit renders form for another user" do
    get edit_admin_user_path(users(:member))
    assert_response :success
    assert_select "form"
  end

  test "edit own account redirects with alert" do
    get edit_admin_user_path(users(:admin))
    assert_redirected_to admin_users_path
    follow_redirect!
    assert_select ".flash-alert", /cannot manage your own/i
  end

  # Update
  test "update changes user attributes" do
    patch admin_user_path(users(:member)), params: { user: { name: "Updated Name" } }
    assert_redirected_to admin_users_path
    assert_equal "Updated Name", users(:member).reload.name
  end

  test "update with blank password keeps existing password" do
    original_password = users(:member).encrypted_password
    patch admin_user_path(users(:member)), params: { user: { name: "Same Pass", password: "" } }
    assert_redirected_to admin_users_path
    assert_equal original_password, users(:member).reload.encrypted_password
  end

  test "update can change role" do
    patch admin_user_path(users(:member)), params: { user: { role: "admin" } }
    assert_redirected_to admin_users_path
    assert users(:member).reload.admin?
  end

  test "update own account redirects with alert" do
    patch admin_user_path(users(:admin)), params: { user: { name: "Nope" } }
    assert_redirected_to admin_users_path
    follow_redirect!
    assert_select ".flash-alert", /cannot manage your own/i
  end

  test "update with duplicate email re-renders form" do
    patch admin_user_path(users(:member)), params: { user: { email: users(:admin).email } }
    assert_response :unprocessable_entity
  end

  test "update address fields" do
    patch admin_user_path(users(:member)), params: { user: {
      address_line1: "123 Main St", city: "Ottawa", province: "ON"
    } }
    assert_redirected_to admin_users_path
    user = users(:member).reload
    assert_equal "123 Main St", user.address_line1
    assert_equal "Ottawa", user.city
    assert_equal "ON", user.province
  end

  # Destroy — admin cannot delete
  test "admin cannot destroy a user" do
    assert_no_difference "User.count" do
      delete admin_user_path(users(:member))
    end
    assert_redirected_to admin_users_path
    follow_redirect!
    assert_select ".flash-alert", /superadmin/i
  end

  test "destroy own account redirects with alert" do
    assert_no_difference "User.count" do
      delete admin_user_path(users(:admin))
    end
    assert_redirected_to admin_users_path
    follow_redirect!
    assert_select ".flash-alert", /cannot manage your own/i
  end
end

class Admin::UsersControllerSuperadminTest < ActionDispatch::IntegrationTest
  setup do
    post user_session_path, params: { email: users(:superadmin).email, password: "password123" }
  end

  test "superadmin can access admin panel" do
    get admin_users_path
    assert_response :success
  end

  test "superadmin can destroy a user" do
    assert_difference "User.count", -1 do
      delete admin_user_path(users(:member))
    end
    assert_redirected_to admin_users_path
  end

  test "superadmin cannot destroy own account" do
    assert_no_difference "User.count" do
      delete admin_user_path(users(:superadmin))
    end
    assert_redirected_to admin_users_path
  end

  test "superadmin can create a superadmin user" do
    assert_difference "User.count", 1 do
      post admin_users_path, params: { user: { email: "newsuper@buildcanada.com", password: "securepass", role: "superadmin" } }
    end
    assert_redirected_to admin_users_path
    user = User.find_by(email: "newsuper@buildcanada.com")
    assert user.superadmin?
    assert user.admin?
  end
end
