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

  test "from_linkedin creates a member with a linkedin identity" do
    auth = OmniAuth::AuthHash.new(
      provider: "linkedin",
      uid: "li-abc",
      info: { email: "lin@example.com", first_name: "Lin", last_name: "Kedin", picture_url: "https://x/p.jpg" },
      extra: { "raw_info" => { "name" => "Lin Kedin" } }
    )
    assert_difference -> { User.count }, 1 do
      User.from_linkedin(auth)
    end
    identity = Identity.find_by(provider: "linkedin", uid: "li-abc")
    assert_not_nil identity
    # Full OAuth payload stored raw on the identity (not on the user).
    assert_equal "Lin Kedin", identity.raw.dig("extra", "raw_info", "name")
    assert_equal "lin@example.com", identity.raw.dig("info", "email")
    user = identity.user
    assert_equal "lin@example.com", user.email
    assert_equal "Lin Kedin", user.name
    assert_equal "https://x/p.jpg", user.avatar_url
    assert user.member?

    assert_no_difference [ -> { User.count }, -> { Identity.count } ] do
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
    assert_equal "No Name", Identity.find_by(provider: "linkedin", uid: "li-noname").user.name
  end

  test "from_linkedin links an identity onto an existing account with the same email, preserving password login" do
    existing = User.create!(email: "merge@example.com", password: "password123", name: "Merge Me")
    auth = OmniAuth::AuthHash.new(
      provider: "linkedin",
      uid: "li-merge",
      info: { email: "merge@example.com", first_name: "Merge", last_name: "Me", picture_url: "https://x/m.jpg" },
      extra: { "raw_info" => { "name" => "Merge Me", "email_verified" => true } }
    )

    assert_no_difference -> { User.count } do
      assert_difference -> { Identity.count }, 1 do
        User.from_linkedin(auth)
      end
    end

    existing.reload
    assert_equal existing, Identity.find_by(provider: "linkedin", uid: "li-merge").user
    assert existing.valid_password?("password123"), "password login should be preserved after linking"
  end

  test "a user can link multiple providers" do
    user = User.create!(email: "multi@example.com", password: "password123", name: "Multi Link")
    User.from_google(provider: "google_oauth2", uid: "g-1", email: "multi@example.com", name: "Multi Link", email_verified: true)
    User.from_linkedin(OmniAuth::AuthHash.new(
      provider: "linkedin", uid: "li-multi",
      info: { email: "multi@example.com", first_name: "Multi", last_name: "Link" },
      extra: { "raw_info" => { "name" => "Multi Link", "email_verified" => true } }
    ))

    assert_equal %w[google_oauth2 linkedin], user.identities.order(:provider).pluck(:provider)
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
    assert_no_difference [ -> { User.count }, -> { Identity.count } ] do
      result = User.from_linkedin(auth)
    end
    refute result.persisted?, "must not link/create when the LinkedIn email is unverified"
    assert_nil Identity.find_by(provider: "linkedin", uid: "li-unverified")
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
