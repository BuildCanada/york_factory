require "test_helper"

class Api::V1::FeedItemsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @feed_item = feed_items(:published_blog)
  end

  test "index returns published feed items" do
    get api_v1_feed_items_url
    assert_response :success
    data = JSON.parse(response.body)["data"]
    assert data.is_a?(Array)
    ids = data.map { |fi| fi["id"] }
    assert_includes ids, @feed_item.id
  end

  test "index excludes draft feed items" do
    get api_v1_feed_items_url
    data = JSON.parse(response.body)["data"]
    ids = data.map { |fi| fi["id"] }
    assert_not_includes ids, feed_items(:draft_blog).id
  end

  test "index filters by type" do
    get api_v1_feed_items_url, params: { type: "blog" }
    assert_response :success
    data = JSON.parse(response.body)["data"]
    data.each { |fi| assert_equal "blog", fi["item_type"] }
  end

  test "index filters by featured" do
    get api_v1_feed_items_url, params: { featured: true }
    assert_response :success
    data = JSON.parse(response.body)["data"]
    data.each { |fi| assert fi["featured"] }
  end

  test "index includes pagination metadata" do
    get api_v1_feed_items_url
    body = JSON.parse(response.body)
    assert body.key?("pagination")
  end

  test "show returns full feed item" do
    get api_v1_feed_item_url(@feed_item)
    assert_response :success
    data = JSON.parse(response.body)
    assert_equal @feed_item.id, data["id"]
    assert data.key?("body")
    assert data.key?("embed_code")
  end
end
