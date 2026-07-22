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

  test "validates name for members" do
    user = User.new(email: "test@example.com", password: "password123", role: "member")
    assert_not user.valid?
    assert user.errors.where(:name, :blank).any?, "expected a blank error on name"
  end

  test "a member may be created without a postal_code (collected later via OAuth signup)" do
    user = User.new(email: "newmember@example.com", password: "password123", role: "member", name: "New Member")
    assert user.valid?, user.errors.full_messages.to_sentence
    assert_not user.engagement_ready?
  end

  test "postal_code must be a valid Canadian format when present" do
    user = User.new(email: "bad@example.com", password: "password123", role: "member", name: "Bad Postal", postal_code: "12345")
    assert_not user.valid?
    assert user.errors.where(:postal_code, :invalid).any?
  end

  test "postal_code is normalized to A1A 1A1 on save" do
    user = User.create!(email: "norm@example.com", password: "password123", role: "member", name: "Norm", postal_code: "m5v2t6")
    assert_equal "M5V 2T6", user.reload.postal_code
  end

  test "engagement_ready? is true once a postal code is set" do
    assert users(:member).engagement_ready?
    refute User.new.engagement_ready?
  end

  test "from_linkedin upserts a member by provider and uid" do
    auth = OmniAuth::AuthHash.new(
      provider: "linkedin",
      uid: "li-abc",
      info: { email: "lin@example.com", first_name: "Lin", last_name: "Kedin", picture_url: "https://x/p.jpg" },
      extra: { "raw_info" => { "name" => "Lin Kedin" } }
    )
    assert_difference -> { User.count }, 1 do
      User.from_linkedin(auth)
    end
    user = User.find_by(provider: "linkedin", uid: "li-abc")
    assert_equal "lin@example.com", user.email
    assert_equal "Lin Kedin", user.name
    assert_equal "https://x/p.jpg", user.avatar_url
    assert user.member?

    assert_no_difference -> { User.count } do
      User.from_linkedin(auth)
    end
  end

  test "from_linkedin falls back to first/last name when raw_info name is absent" do
    auth = OmniAuth::AuthHash.new(
      provider: "linkedin",
      uid: "li-noname",
      info: { email: "nn@example.com", first_name: "No", last_name: "Name", picture_url: nil }
    )
    User.from_linkedin(auth)
    assert_equal "No Name", User.find_by(provider: "linkedin", uid: "li-noname").name
  end

  test "from_linkedin links onto an existing account with the same email, preserving password login" do
    existing = User.create!(email: "merge@example.com", password: "password123", name: "Merge Me")
    auth = OmniAuth::AuthHash.new(
      provider: "linkedin",
      uid: "li-merge",
      info: { email: "merge@example.com", first_name: "Merge", last_name: "Me", picture_url: "https://x/m.jpg" },
      extra: { "raw_info" => { "name" => "Merge Me", "email_verified" => true } }
    )

    assert_no_difference -> { User.count } do
      User.from_linkedin(auth)
    end

    existing.reload
    assert_equal "linkedin", existing.provider
    assert_equal "li-merge", existing.uid
    assert existing.valid_password?("password123"), "password login should be preserved after linking"
  end

  test "from_linkedin does not link onto an existing email when LinkedIn reports it unverified" do
    User.create!(email: "unverified@example.com", password: "password123", name: "Real Owner")
    auth = OmniAuth::AuthHash.new(
      provider: "linkedin",
      uid: "li-unverified",
      info: { email: "unverified@example.com", first_name: "Imp", last_name: "Oster" },
      extra: { "raw_info" => { "name" => "Imp Oster", "email_verified" => false } }
    )

    result = nil
    assert_no_difference -> { User.count } do
      result = User.from_linkedin(auth)
    end
    refute result.persisted?, "must not link/create when the LinkedIn email is unverified"
    assert_nil User.find_by(provider: "linkedin", uid: "li-unverified")
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
