require "test_helper"

class SubstackPostTest < ActiveSupport::TestCase
  test "valid substack post" do
    post = substack_posts(:substack_newsletter)
    assert post.valid?
  end

  test "requires external_url" do
    post = SubstackPost.new(title: "Test", posted_at: Time.current)
    assert_not post.valid?
    assert post.errors.where(:external_url, :blank).any?
  end

  test "requires unique external_url" do
    existing = substack_posts(:substack_newsletter)
    duplicate = SubstackPost.new(
      external_url: existing.external_url,
      title: "Duplicate",
      posted_at: Time.current
    )
    assert_not duplicate.valid?
  end

  test "requires title" do
    post = SubstackPost.new(external_url: "https://example.com/unique", posted_at: Time.current)
    assert_not post.valid?
    assert post.errors.where(:title, :blank).any?
  end

  test "feed_type_label returns substack" do
    assert_equal "substack", SubstackPost.feed_type_label
  end

  test "feed_published_at returns posted_at" do
    post = substack_posts(:substack_newsletter)
    assert_equal post.posted_at, post.feed_published_at
  end
end
