require "test_helper"

class TeamMemberTest < ActiveSupport::TestCase
  setup do
    I18n.locale = :en
  end

  teardown do
    I18n.locale = I18n.default_locale
  end

  test "requires a name" do
    member = TeamMember.new
    assert_not member.valid?
    assert_includes member.errors[:name], "can't be blank"
  end

  test "slug is generated from name via FriendlyId" do
    member = TeamMember.new(name: "Jane Doe")
    member.valid?
    assert_equal "jane-doe", member.slug
  end

  test "role must be in allowed list" do
    member = TeamMember.new(name: "Test", slug: "test-slug", role: "unknown-role")
    assert_not member.valid?
    assert_includes member.errors[:role], "is not included in the list"
  end

  test "nil role is valid" do
    member = TeamMember.new(name: "No Role", slug: "no-role-member")
    assert member.valid?, member.errors.full_messages.inspect
  end

  test "valid roles are accepted" do
    %w[board team volunteer advisor].each do |valid_role|
      member = TeamMember.new(name: "Test #{valid_role}", slug: "test-#{valid_role}-#{SecureRandom.hex(4)}", role: valid_role)
      assert member.valid?, "Expected role '#{valid_role}' to be valid: #{member.errors.full_messages}"
    end
  end

  test "ordered scope returns members sorted by position" do
    ordered = TeamMember.ordered.to_a
    positions = ordered.map(&:position)
    assert_equal positions.sort, positions
  end

  test "by_role scope filters by role" do
    team = TeamMember.by_role("team")
    assert_includes team, team_members(:alice)
    assert_not_includes team, team_members(:bob)
  end

  test "fixture alice has correct attributes" do
    alice = team_members(:alice)
    assert_equal "Alice Builder", alice.name
    assert_equal "alice-builder", alice.slug
    assert_equal "team", alice.role
    assert_equal 1, alice.position
    assert_equal "Director of Engineering", alice.title_en
  end

  test "Mobility fallback returns EN when FR is nil" do
    member = TeamMember.new(name: "Test", title_en: "Engineer")
    I18n.locale = :fr
    assert_equal "Engineer", member.title
  end
end
