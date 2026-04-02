require "test_helper"

class Api::V1::MemosControllerTest < ActionDispatch::IntegrationTest
  test "index returns published memos" do
    get api_v1_memos_url
    assert_response :success

    data = JSON.parse(response.body)
    slugs = data["data"].map { |m| m["slug"] }

    assert_includes slugs, "housing-crisis-memo"
    assert_not_includes slugs, "draft-memo"
  end

  test "index returns pagination metadata" do
    get api_v1_memos_url
    assert_response :success

    data = JSON.parse(response.body)
    assert data.key?("pagination")
    assert data["pagination"].key?("page")
    assert data["pagination"].key?("count")
  end

  test "index filters by category" do
    get api_v1_memos_url, params: { category: "housing" }
    assert_response :success

    data = JSON.parse(response.body)
    slugs = data["data"].map { |m| m["slug"] }
    assert_includes slugs, "housing-crisis-memo"
  end

  test "index filters out non-matching categories" do
    get api_v1_memos_url, params: { category: "defence" }
    assert_response :success

    data = JSON.parse(response.body)
    assert_empty data["data"]
  end

  test "index filters by featured" do
    get api_v1_memos_url, params: { featured: "1" }
    assert_response :success

    data = JSON.parse(response.body)
    slugs = data["data"].map { |m| m["slug"] }
    assert_includes slugs, "housing-crisis-memo"
  end

  test "index filters by search query" do
    get api_v1_memos_url, params: { q: "Housing Crisis" }
    assert_response :success

    data = JSON.parse(response.body)
    slugs = data["data"].map { |m| m["slug"] }
    assert_includes slugs, "housing-crisis-memo"
  end

  test "index returns no results for unmatched search query" do
    get api_v1_memos_url, params: { q: "zzznomatch" }
    assert_response :success

    data = JSON.parse(response.body)
    assert_empty data["data"]
  end

  test "show returns a published memo by slug" do
    get api_v1_memo_url("housing-crisis-memo")
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal "housing-crisis-memo", data["slug"]
    assert_equal "Housing Crisis Analysis", data["title"]
    assert data.key?("body")
  end

  test "show includes author when present" do
    get api_v1_memo_url("housing-crisis-memo")
    assert_response :success

    data = JSON.parse(response.body)
    assert_not_nil data["author"]
    assert_equal "Alice Builder", data["author"]["name"]
    assert_equal "alice-builder", data["author"]["slug"]
  end

  test "show returns French content when locale=fr" do
    get api_v1_memo_url("housing-crisis-memo"), params: { locale: "fr" }
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal "Analyse de la crise du logement", data["title"]
  end

  test "show returns 404 for nonexistent slug" do
    get api_v1_memo_url("nonexistent-slug")
    assert_response :not_found
  end

  test "create without auth returns 401" do
    post api_v1_memos_url, params: {
      memo: {
        title_en: "New Memo",
        body_en: "<p>Body</p>"
      }
    }, as: :json

    assert_response :unauthorized
  end

  test "destroy without auth returns 401" do
    delete api_v1_memo_url("housing-crisis-memo")
    assert_response :unauthorized
  end
end
