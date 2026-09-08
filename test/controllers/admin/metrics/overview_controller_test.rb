require "test_helper"

class Admin::Metrics::OverviewControllerTest < ActionDispatch::IntegrationTest
  include AdminTestHelper

  setup do
    sign_in_admin
  end

  test "overview renders" do
    get admin_metrics_root_path
    assert_response :success
    assert_select "h1", "Metrics Overview"
  end

  test "Build Canada Instagram reports that it is synced from the Meta Graph API" do
    Metrics::MetaAccount.create!(
      platform: "instagram",
      account_key: "build_canada",
      platform_account_id: "ig-build-canada",
      last_synced_at: Time.current
    )

    get admin_metrics_root_path
    assert_response :success

    card = card_for("Build Canada Instagram")
    assert_includes card, "Synced from the Meta Graph API"
    refute_includes card, "New Week",
      "the API card must not offer manual weekly entry"
  end

  test "the manual weekly form stays available alongside the API card" do
    get admin_metrics_root_path
    assert_response :success

    card = card_for("Build Canada Instagram (manual weekly)")
    assert_includes card, "New Week"
    assert_includes card, "backfill only"
  end

  private

  # The overview renders one .card per source, so scope assertions to the card
  # whose label matches; "Build Canada Instagram" is otherwise a prefix of the
  # manual card's name.
  def card_for(name)
    card = css_select(".card").find do |node|
      # The label carries a trailing ↗ on sources that link out to analytics.
      node.css(".label").text.strip.sub(/\s*↗\z/, "") == name
    end
    assert card, "no card found for #{name.inspect}"
    card.to_html
  end
end
