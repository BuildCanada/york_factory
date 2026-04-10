require "test_helper"

class SocialPostTest < ActiveSupport::TestCase
  test "valid x post" do
    post = social_posts(:x_post)
    assert post.valid?
    assert_instance_of SocialPost::X, post
  end

  test "valid instagram post" do
    post = social_posts(:ig_post)
    assert post.valid?
    assert_instance_of SocialPost::Instagram, post
  end

  test "valid instagram reel" do
    post = social_posts(:ig_reel)
    assert post.valid?
    assert_instance_of SocialPost::InstagramReel, post
  end

  test "valid tiktok post" do
    post = social_posts(:tiktok_post)
    assert post.valid?
    assert_instance_of SocialPost::TikTok, post
  end

  test "requires external_id" do
    post = SocialPost::X.new(url: "https://x.com/test", account_handle: "@test")
    assert_not post.valid?
    assert post.errors.where(:external_id, :blank).any?
  end

  test "requires unique external_id per type" do
    existing = social_posts(:x_post)
    duplicate = SocialPost::X.new(
      external_id: existing.external_id,
      url: "https://x.com/other",
      account_handle: "@test",
      posted_at: Time.current
    )
    assert_not duplicate.valid?
  end

  test "same external_id allowed across different types" do
    post = SocialPost::Instagram.new(
      external_id: social_posts(:x_post).external_id,
      url: "https://instagram.com/test",
      account_handle: "@test",
      posted_at: Time.current
    )
    assert post.valid?
  end

  test "feed_type_label returns correct label for each subclass" do
    assert_equal "x", SocialPost::X.feed_type_label
    assert_equal "ig", SocialPost::Instagram.feed_type_label
    assert_equal "ig", SocialPost::InstagramReel.feed_type_label
    assert_equal "tiktok", SocialPost::TikTok.feed_type_label
  end

  test "feed_published_at returns posted_at" do
    post = social_posts(:x_post)
    assert_equal post.posted_at, post.feed_published_at
  end
end
