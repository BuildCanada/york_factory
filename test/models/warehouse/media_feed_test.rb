require "test_helper"

class Warehouse::MediaFeedTest < ActiveSupport::TestCase
  test "stores media feed metadata in dedicated columns" do
    feed = Warehouse::MediaFeed.create!(
      name: "Test feed #{SecureRandom.hex(4)}",
      url: "https://news.example.com/feed",
      publisher_name: "Example News",
      publisher_domain: "www.example.com",
      language: "fr",
      cadence_seconds: 600
    )

    assert_equal "rss", feed.strategy
    assert_equal "example.com", feed.publisher_domain
    assert_equal "Example News", feed.reload.publisher_name
    assert feed.enabled?
  end

  test "requires publisher metadata and a secure URL" do
    feed = Warehouse::MediaFeed.new(name: "Invalid feed", url: "http://example.com/feed")

    assert_not feed.valid?
    assert_includes feed.errors[:publisher_name], "can't be blank"
    assert_includes feed.errors[:url], "must use HTTPS"
  end

  test "resolves publisher aliases from feed metadata" do
    feed = Warehouse::MediaFeed.new(
      publisher_name: "Financial Post",
      publisher_domain: "financialpost.com"
    )

    assert_equal(
      { "name" => "Financial Post", "domain" => "financialpost.com" },
      Warehouse::MediaFeed.publisher_for("business.financialpost.com", feed:)
    )
  end

  test "publisher list is read from persisted feeds" do
    Warehouse::MediaFeed.create!(
      name: "Publisher list #{SecureRandom.hex(4)}",
      url: "https://publisher-list.example/feed",
      publisher_name: "Publisher List",
      publisher_domain: "publisher-list.example",
      language: "en"
    )

    assert_includes Warehouse::MediaFeed.publishers,
      { "name" => "Publisher List", "domain" => "publisher-list.example" }
  end

  test "changing a feed URL clears conditional request state" do
    feed = Warehouse::MediaFeed.create!(
      name: "Changed feed #{SecureRandom.hex(4)}",
      url: "https://changed-feed.example/old",
      publisher_name: "Changed Feed",
      publisher_domain: "changed-feed.example",
      language: "en"
    )
    feed.update_columns(
      etag: "old-etag",
      last_modified: "yesterday",
      consecutive_failures: 3
    )

    feed.update!(url: "https://changed-feed.example/new")

    assert_nil feed.etag
    assert_nil feed.last_modified
    assert_equal 0, feed.consecutive_failures
    assert feed.next_fetch_at.present?
  end

  test "bootstrap creates missing feeds without overwriting admin changes" do
    seed_file = Rails.root.join("db/seeds/media_feeds.rb")
    load seed_file
    national_post = Warehouse::MediaFeed.find_by!(name: "National Post")
    national_post.update!(enabled: false, cadence_seconds: 900)

    assert_no_difference -> { Warehouse::MediaFeed.count } do
      load seed_file
    end

    assert_not national_post.reload.enabled?
    assert_equal 900, national_post.cadence_seconds
    assert_equal 1, Warehouse::MediaFeed.where(name: "National Post").count
  end
end
