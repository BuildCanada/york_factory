require "test_helper"

class FeedEntryTest < ActiveSupport::TestCase
  test "valid feed entry with memo" do
    entry = feed_entries(:memo_entry)
    assert entry.valid?
    assert_equal "Memo", entry.feedable_type
  end

  test "valid feed entry with social post" do
    entry = feed_entries(:x_entry)
    assert entry.valid?
    assert_equal "SocialPost::X", entry.feedable_type
  end

  test "published scope returns entries with past published_at" do
    published = FeedEntry.published
    published.each do |entry|
      assert entry.published_at <= Time.current
    end
  end

  test "featured scope returns only featured entries" do
    featured = FeedEntry.featured
    featured.each { |entry| assert entry.featured }
  end

  test "by_type scope filters by feedable_type" do
    memos = FeedEntry.by_type("Memo")
    memos.each { |entry| assert_equal "Memo", entry.feedable_type }
  end

  test "chronological scope orders by published_at desc" do
    entries = FeedEntry.chronological.to_a
    entries.each_cons(2) do |a, b|
      assert a.published_at >= b.published_at
    end
  end

  test "unique constraint on feedable_type and feedable_id" do
    existing = feed_entries(:memo_entry)
    duplicate = FeedEntry.new(
      feedable_type: existing.feedable_type,
      feedable_id: existing.feedable_id,
      published_at: Time.current
    )
    assert_raises(ActiveRecord::RecordNotUnique) { duplicate.save!(validate: false) }
  end
end
