require "test_helper"

class Api::V1::BuildersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @builder = builders(:published_builder)
  end

  test "index returns published builders" do
    get api_v1_builders_url
    assert_response :success
    data = JSON.parse(response.body)["data"]
    assert data.is_a?(Array)
    slugs = data.map { |b| b["slug"] }
    assert_includes slugs, @builder.slug
  end

  test "index excludes draft builders" do
    get api_v1_builders_url
    data = JSON.parse(response.body)["data"]
    slugs = data.map { |b| b["slug"] }
    assert_not_includes slugs, builders(:draft_builder).slug
  end

  test "index includes pagination metadata" do
    get api_v1_builders_url
    body = JSON.parse(response.body)
    assert body.key?("pagination")
    assert body["pagination"].key?("page")
  end

  test "show returns builder by slug" do
    get api_v1_builder_url(slug: @builder.slug)
    assert_response :success
    data = JSON.parse(response.body)
    assert_equal @builder.slug, data["slug"]
    assert data.key?("body")
  end

  test "show returns not found for draft builder" do
    get api_v1_builder_url(slug: builders(:draft_builder).slug)
    assert_response :not_found
  end

  test "index respects locale param for french" do
    get api_v1_builders_url, params: { locale: "fr" }
    assert_response :success
    data = JSON.parse(response.body)["data"]
    builder_data = data.find { |b| b["slug"] == @builder.slug }
    assert_equal @builder.title_fr, builder_data["title"]
  end
end
