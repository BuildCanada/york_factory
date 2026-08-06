require "test_helper"

class Admin::MediaFeedsControllerTest < ActionDispatch::IntegrationTest
  include AdminTestHelper

  setup do
    sign_in_admin
    @feed = Warehouse::MediaFeed.create!(
      name: "Admin feed #{SecureRandom.hex(4)}",
      url: "https://admin-feed.example/feed",
      publisher_name: "Admin News",
      publisher_domain: "admin-feed.example",
      language: "en",
      cadence_seconds: 300
    )
  end

  test "lists media feeds" do
    get admin_media_feeds_path

    assert_response :success
    assert_select "h1", "Media Feeds"
    assert_select "td", text: /#{Regexp.escape(@feed.name)}/
  end

  test "renders new and edit forms" do
    get new_admin_media_feed_path
    assert_response :success
    assert_select "form[action='#{admin_media_feeds_path}']"

    get edit_admin_media_feed_path(@feed)
    assert_response :success
    assert_select "form[action='#{admin_media_feed_path(@feed)}']"
  end

  test "creates a feed" do
    assert_difference -> { Warehouse::MediaFeed.count }, 1 do
      post admin_media_feeds_path, params: {
        media_feed: {
          name: "New feed #{SecureRandom.hex(4)}",
          url: "https://new-feed.example/rss",
          publisher_name: "New Publisher",
          publisher_domain: "new-feed.example",
          language: "fr",
          strategy: "rss",
          cadence_seconds: 600,
          enabled: "1"
        }
      }
    end

    assert_redirected_to admin_media_feeds_path
  end

  test "updates feed metadata" do
    patch admin_media_feed_path(@feed), params: {
      media_feed: {
        name: @feed.name,
        url: @feed.url,
        publisher_name: "Renamed News",
        publisher_domain: @feed.publisher_domain,
        language: @feed.language,
        strategy: @feed.strategy,
        cadence_seconds: @feed.cadence_seconds,
        enabled: "1"
      }
    }

    assert_redirected_to admin_media_feeds_path
    assert_equal "Renamed News", @feed.reload.publisher_name
  end

  test "toggles feed enablement and schedules enabled feeds" do
    patch toggle_admin_media_feed_path(@feed)
    assert_not @feed.reload.enabled?

    @feed.update_column(:next_fetch_at, nil)
    patch toggle_admin_media_feed_path(@feed)

    assert @feed.reload.enabled?
    assert @feed.next_fetch_at.present?
  end
end
