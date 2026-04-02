require "test_helper"

class FeedItemTest < ActiveSupport::TestCase
  setup { I18n.locale = :en }
  teardown { I18n.locale = :en }

  test "valid feed item" do
    item = FeedItem.new(item_type: "blog", source_url: "https://unique-#{SecureRandom.hex}.com")
    assert item.valid?
  end

  test "requires item_type" do
    item = FeedItem.new(source_url: "https://example.com/unique")
    assert_not item.valid?
    assert_includes item.errors[:item_type], "can't be blank"
  end

  test "validates item_type inclusion" do
    item = FeedItem.new(item_type: "invalid", source_url: "https://example.com/unique2")
    assert_not item.valid?
    assert_includes item.errors[:item_type], "is not included in the list"
  end

  test "requires unique source_url" do
    existing = feed_items(:published_blog)
    item = FeedItem.new(item_type: "blog", source_url: existing.source_url)
    assert_not item.valid?
    assert_includes item.errors[:source_url], "has already been taken"
  end

  test "requires source_url presence" do
    item = FeedItem.new(item_type: "blog")
    assert_not item.valid?
    assert_includes item.errors[:source_url], "can't be blank"
  end

  test "featured scope returns only featured items" do
    featured = FeedItem.featured
    featured.each { |fi| assert fi.featured }
  end

  test "by_type scope filters by item_type" do
    blogs = FeedItem.by_type("blog")
    blogs.each { |fi| assert_equal "blog", fi.item_type }
  end

  test "published scope excludes draft items" do
    published = FeedItem.published
    published.each do |fi|
      assert fi.published_at.present?
      assert fi.published_at <= Time.current
    end
  end
end
