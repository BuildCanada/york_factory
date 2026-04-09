require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "member? is true only for members" do
    assert users(:member).member?
    assert_not users(:admin).member?
    assert_not users(:superadmin).member?
  end

  test "admin? is true for admin role" do
    assert users(:admin).admin?
  end

  test "admin? is true for superadmin role" do
    assert users(:superadmin).admin?
  end

  test "admin? is false for member role" do
    assert_not users(:member).admin?
  end

  test "superadmin? is true only for superadmin role" do
    assert users(:superadmin).superadmin?
    assert_not users(:admin).superadmin?
    assert_not users(:member).superadmin?
  end

  test "validates email presence and uniqueness" do
    user = User.new(role: "admin", password: "password123")
    assert_not user.valid?
    assert user.errors.where(:email, :blank).any?, "expected a blank error on email"
  end

  test "validates name and postal_code for members" do
    user = User.new(email: "test@example.com", password: "password123", role: "member")
    assert_not user.valid?
    assert user.errors.where(:name, :blank).any?, "expected a blank error on name"
    assert user.errors.where(:postal_code, :blank).any?, "expected a blank error on postal_code"
  end

  test "admin does not require name or postal_code" do
    user = User.new(email: "noadmin@test.com", password: "password123", role: "admin")
    assert user.valid?
  end

  test "superadmin does not require name or postal_code" do
    user = User.new(email: "nosuper@test.com", password: "password123", role: "superadmin")
    assert user.valid?
  end
end
