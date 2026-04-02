require "test_helper"

class Admin::AdminRoutesTest < ActionDispatch::IntegrationTest
  include AdminTestHelper

  setup do
    sign_in_admin
  end

  # Dashboard
  test "dashboard index renders" do
    get admin_root_path
    assert_response :success
  end

  # Posts
  test "posts index renders" do
    get admin_posts_path
    assert_response :success
  end

  test "posts show renders" do
    get admin_post_path(posts(:visible_post))
    assert_response :success
  end

  test "posts new renders" do
    get new_admin_post_path
    assert_response :success
  end

  test "posts edit renders" do
    get edit_admin_post_path(posts(:visible_post))
    assert_response :success
  end

  # Memos
  test "memos index renders" do
    get admin_memos_path
    assert_response :success
  end

  test "memos show renders" do
    get admin_memo_path(memos(:published_memo))
    assert_response :success
  end

  test "memos new renders" do
    get new_admin_memo_path
    assert_response :success
  end

  test "memos edit renders" do
    get edit_admin_memo_path(memos(:published_memo))
    assert_response :success
  end

  # Builders
  test "builders index renders" do
    get admin_builders_path
    assert_response :success
  end

  test "builders show renders" do
    get admin_builder_path(builders(:published_builder))
    assert_response :success
  end

  test "builders new renders" do
    get new_admin_builder_path
    assert_response :success
  end

  test "builders edit renders" do
    get edit_admin_builder_path(builders(:published_builder))
    assert_response :success
  end

  # Team Members
  test "team_members index renders" do
    get admin_team_members_path
    assert_response :success
  end

  test "team_members show renders" do
    get admin_team_member_path(team_members(:alice))
    assert_response :success
  end

  test "team_members new renders" do
    get new_admin_team_member_path
    assert_response :success
  end

  test "team_members edit renders" do
    get edit_admin_team_member_path(team_members(:alice))
    assert_response :success
  end

  # Tools
  test "tools index renders" do
    get admin_tools_path
    assert_response :success
  end

  test "tools show renders" do
    get admin_tool_path(tools(:featured_tool))
    assert_response :success
  end

  test "tools new renders" do
    get new_admin_tool_path
    assert_response :success
  end

  test "tools edit renders" do
    get edit_admin_tool_path(tools(:featured_tool))
    assert_response :success
  end

  # FAQs
  test "faqs index renders" do
    get admin_faqs_path
    assert_response :success
  end

  test "faqs show renders" do
    get admin_faq_path(faqs(:published_faq))
    assert_response :success
  end

  test "faqs new renders" do
    get new_admin_faq_path
    assert_response :success
  end

  test "faqs edit renders" do
    get edit_admin_faq_path(faqs(:published_faq))
    assert_response :success
  end

  # Feed Items
  test "feed_items index renders" do
    get admin_feed_items_path
    assert_response :success
  end

  test "feed_items show renders" do
    get admin_feed_item_path(feed_items(:published_blog))
    assert_response :success
  end

  test "feed_items new renders" do
    get new_admin_feed_item_path
    assert_response :success
  end

  test "feed_items edit renders" do
    get edit_admin_feed_item_path(feed_items(:published_blog))
    assert_response :success
  end

  # Testimonials
  test "testimonials index renders" do
    get admin_testimonials_path
    assert_response :success
  end

  test "testimonials show renders" do
    get admin_testimonial_path(testimonials(:published_testimonial))
    assert_response :success
  end

  test "testimonials new renders" do
    get new_admin_testimonial_path
    assert_response :success
  end

  test "testimonials edit renders" do
    get edit_admin_testimonial_path(testimonials(:published_testimonial))
    assert_response :success
  end

  # Subscribers
  test "subscribers index renders" do
    get admin_subscribers_path
    assert_response :success
  end

  # Auth guard
  test "unauthenticated request redirects to login" do
    reset!
    get admin_posts_path
    assert_response :redirect
    assert_redirected_to admin_login_path
  end
end
