require "test_helper"

class Api::V1::TeamMembersControllerTest < ActionDispatch::IntegrationTest
  test "index returns ordered team members" do
    get api_v1_team_members_url
    assert_response :success

    data = JSON.parse(response.body)
    assert data.key?("data")
    assert data["data"].length >= 2

    positions = data["data"].map { |m| m["position"] }
    assert_equal positions.sort, positions
  end

  test "index includes expected member fields" do
    get api_v1_team_members_url
    assert_response :success

    data = JSON.parse(response.body)
    member = data["data"].find { |m| m["slug"] == "alice-builder" }

    assert_not_nil member
    assert_equal "Alice Builder", member["name"]
    assert_equal "alice-builder", member["slug"]
    assert_equal "team", member["role"]
    assert_equal "Director of Engineering", member["title"]
  end

  test "index filters by role" do
    get api_v1_team_members_url, params: { role: "team" }
    assert_response :success

    data = JSON.parse(response.body)
    roles = data["data"].map { |m| m["role"] }

    assert roles.all? { |r| r == "team" }
    assert roles.any?
  end

  test "index role filter excludes other roles" do
    get api_v1_team_members_url, params: { role: "board" }
    assert_response :success

    data = JSON.parse(response.body)
    slugs = data["data"].map { |m| m["slug"] }

    assert_not_includes slugs, "alice-builder"
    assert_not_includes slugs, "bob-advisor"
  end

  test "index returns French title when locale=fr" do
    get api_v1_team_members_url, params: { locale: "fr" }
    assert_response :success

    data = JSON.parse(response.body)
    alice = data["data"].find { |m| m["slug"] == "alice-builder" }

    assert_not_nil alice
    assert_equal "Directrice de l'ingénierie", alice["title"]
  end

  test "create without auth returns 401" do
    post api_v1_team_members_url, params: {
      team_member: { name: "New Member", role: "team" }
    }, as: :json

    assert_response :unauthorized
  end
end
