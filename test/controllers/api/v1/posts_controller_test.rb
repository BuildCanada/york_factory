require "test_helper"

class Api::V1::PostsControllerTest < ActionDispatch::IntegrationTest
  test "index excludes hidden posts" do
    get api_v1_posts_url
    assert_response :success

    data = JSON.parse(response.body)
    slugs = data["data"].map { |p| p["slug"] }

    assert_includes slugs, "first-post"
    assert_not_includes slugs, "hidden-post"
  end

  test "index returns pagination metadata" do
    get api_v1_posts_url
    assert_response :success

    data = JSON.parse(response.body)
    assert data.key?("pagination")
  end

  test "show returns a visible post by slug" do
    get api_v1_post_url("first-post")
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal "first-post", data["slug"]
    assert_equal "First Post", data["title"]
    assert data.key?("body")
  end

  test "show returns French content when locale=fr" do
    get api_v1_post_url("first-post"), params: { locale: "fr" }
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal "Premier article", data["title"]
  end

  test "show returns 404 for nonexistent slug" do
    get api_v1_post_url("nonexistent-slug")
    assert_response :not_found
  end

  test "create without auth returns 401" do
    post api_v1_posts_url, params: {
      post: {
        title_en: "New Post",
        body_en: "<p>Body</p>"
      }
    }, as: :json

    assert_response :unauthorized
  end
end
