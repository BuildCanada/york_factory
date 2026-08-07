require "test_helper"

class Api::V1::MemosControllerTest < ActionDispatch::IntegrationTest
  setup do
    _, @admin_api_key = ApiKey.issue!(user: users(:admin), name: "memo-api-#{SecureRandom.hex(3)}")
  end

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

  test "admin API key creates a Build Toronto memo as a draft and cannot set published_at" do
    post api_v1_memos_url, params: {
      memo: {
        slug: "api-created-toronto-memo",
        title_en: "API-created Toronto memo",
        body_en: "## Recommendation\n\nBuild it.",
        appendix_en: "1. Source",
        key_messages_en: [ "First", "Second", "Third" ],
        author_name: "Eric Richmond",
        author_title: "Country Director & CEO at Coinbase Canada",
        publication: "build_toronto",
        published_at: 1.day.ago.iso8601
      }
    }, headers: api_key_headers, as: :json

    assert_response :created
    body = response.parsed_body
    assert_equal "build_toronto", body["publication"]
    assert_nil body["published_at"]

    memo = Memo.find_by!(slug: "api-created-toronto-memo", publication: "build_toronto")
    assert memo.draft?
    assert_equal [ "First", "Second", "Third" ], memo.key_messages_en
  end

  test "API key cannot publish a draft through update" do
    memo = Memo.create!(slug: "api-update-draft", title_en: "API update draft", publication: "build_toronto")

    patch api_v1_memo_url(memo.slug), params: {
      publication: "build_toronto",
      memo: { title_en: "Still a draft", published_at: Time.current.iso8601 }
    }, headers: api_key_headers, as: :json

    assert_response :success
    assert_nil memo.reload.published_at
  end

  test "member API key has member permissions and cannot create a memo" do
    _, raw = ApiKey.issue!(user: users(:member), name: "member-memo-key")

    post api_v1_memos_url, params: { memo: { title_en: "No access" } },
      headers: { "Authorization" => "Bearer #{raw}" }, as: :json

    assert_response :forbidden
  end

  test "admin API key can upload an inline figure" do
    assert_difference "ActiveStorage::Blob.count", 1 do
      post api_v1_uploads_url,
        params: { file: fixture_file_upload("test-image.jpg", "image/jpeg") },
        headers: api_key_headers
    end

    assert_response :created
    assert response.parsed_body["signed_id"].present?
    assert response.parsed_body["url"].present?
  end

  test "admin API key can attach banner and SEO images to a draft" do
    post api_v1_memos_url, params: {
      memo: {
        slug: "api-memo-with-images",
        title_en: "API memo with images",
        publication: "build_toronto",
        banner_image: fixture_file_upload("test-image.jpg", "image/jpeg"),
        seo_image: fixture_file_upload("test-image.jpg", "image/jpeg")
      }
    }, headers: api_key_headers

    assert_response :created
    memo = Memo.find_by!(slug: "api-memo-with-images", publication: "build_toronto")
    assert memo.banner_image.attached?
    assert memo.seo_image.attached?
    assert memo.draft?
  end

  test "destroy without auth returns 401" do
    delete api_v1_memo_url("housing-crisis-memo")
    assert_response :unauthorized
  end

  test "index excludes memos tagged with a publication by default" do
    get api_v1_memos_url
    assert_response :success

    slugs = JSON.parse(response.body)["data"].map { |m| m["slug"] }
    assert_not_includes slugs, "toronto-transit-memo"
  end

  test "index returns only the requested publication when filtered" do
    get api_v1_memos_url, params: { publication: "build_toronto" }
    assert_response :success

    data = JSON.parse(response.body)["data"]
    slugs = data.map { |m| m["slug"] }
    assert_includes slugs, "toronto-transit-memo"
    assert_not_includes slugs, "housing-crisis-memo"
  end

  test "show 404s when slug belongs to a different publication" do
    get api_v1_memo_url("toronto-transit-memo")
    assert_response :not_found
  end

  test "show returns memo when publication matches" do
    get api_v1_memo_url("toronto-transit-memo"), params: { publication: "build_toronto" }
    assert_response :success
    data = JSON.parse(response.body)
    assert_equal "build_toronto", data["publication"]
  end

  test "serialized payload includes publication field" do
    get api_v1_memo_url("housing-crisis-memo")
    assert_response :success
    data = JSON.parse(response.body)
    assert_equal "build_canada", data["publication"]
  end

  private

  def api_key_headers
    { "Authorization" => "Bearer #{@admin_api_key}" }
  end
end
