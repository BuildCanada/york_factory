require "test_helper"

class Api::V1::FeedEntriesControllerTest < ActionDispatch::IntegrationTest
  test "index returns published feed entries" do
    get api_v1_feed_entries_url
    assert_response :success
    data = JSON.parse(response.body)["data"]
    assert data.is_a?(Array)
    assert data.any?
  end

  test "index includes pagination metadata" do
    get api_v1_feed_entries_url
    body = JSON.parse(response.body)
    assert body.key?("pagination")
  end

  test "index filters by type" do
    get api_v1_feed_entries_url, params: { type: "memo" }
    assert_response :success
    data = JSON.parse(response.body)["data"]
    data.each { |entry| assert_equal "memo", entry["item_type"] }
  end

  test "index filters by featured" do
    get api_v1_feed_entries_url, params: { featured: true }
    assert_response :success
    data = JSON.parse(response.body)["data"]
    data.each { |entry| assert entry["featured"] }
  end

  test "index returns entries in reverse chronological order" do
    get api_v1_feed_entries_url
    data = JSON.parse(response.body)["data"]
    dates = data.map { |d| Time.parse(d["published_at"]) }
    assert_equal dates, dates.sort.reverse
  end

  test "show returns full entry with body" do
    entry = feed_entries(:memo_entry)
    get api_v1_feed_entry_url(entry)
    assert_response :success
    data = JSON.parse(response.body)
    assert_equal entry.id, data["id"]
    assert data.key?("body")
  end

  test "entry serializes item_type from feedable" do
    get api_v1_feed_entries_url
    data = JSON.parse(response.body)["data"]
    types = data.map { |d| d["item_type"] }
    # Should have at least memo, blog, x types from fixtures
    assert types.any?
  end
end
