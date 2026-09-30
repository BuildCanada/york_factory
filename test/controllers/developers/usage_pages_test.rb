require "test_helper"

# The console's usage charts (/developers, key detail, the live panel, CSV)
# and the admin's top consumers.
class Developers::UsagePagesTest < ActionDispatch::IntegrationTest
  include AdminTestHelper

  setup do
    @user = users(:member)
    @issued = issue_key(user: @user, name: "Dashboard key")
    @key = @issued.api_key
    @account = @key.account
    now = Time.current.utc
    Usage::Daily.create!(account: @account, api_key_id: @key.id, operation: "getEntity", day: now.to_date, units: 81_000, requests: 81_000,
      errors_4xx: 12, rolled_up_at: now)
    Usage::Daily.create!(account: @account, api_key_id: @key.id, operation: "searchEntities", day: now.to_date - 1, units: 900, requests: 300,
      throttled: 4, errors_4xx: 4, rolled_up_at: now)
    Usage::Hourly.create!(account: @account, api_key_id: @key.id, operation: "getEntity", hour_start: now.beginning_of_hour, units: 81_000,
      requests: 81_000, rolled_up_at: now)
    Usage::RollupRun.create!(window_start: 2.hours.ago, window_end: 1.hour.from_now, source: "analytics_engine", finished_at: now)
  end

  def sign_in_member = post(user_session_path, params: { email: @user.email, password: "password123" })

  test "the overview shows units against the quota, units by day, errors and top operations" do
    sign_in_member
    get developers_path
    assert_response :success
    assert_select ".card .value", text: /81,900\s*\/ 100,000/
    assert_select "[role=meter][aria-valuenow='81900']"
    assert_select ".card", text: /18,100 remaining \(81\.9% used\)/
    assert_select "figure figcaption", text: "Units by day, last 30 days"
    assert_select "figure figcaption", text: "Errors (4xx and 5xx) by day"
    assert_select "figure figcaption", text: "Rate-limited (429) requests by day"
    assert_select "svg.usage-chart title", text: /81,000 units/
    assert_select "td.mono", text: "getEntity"
    assert_select "a[href=?]", developers_usage_path(format: :csv)
  end

  test "key detail: live minutes, hours, days and operations; the live panel refreshes on its own" do
    sign_in_member
    get developers_key_path(@key)
    assert_response :success
    assert_select "#live-usage[data-live-url=?]", live_developers_key_path(@key)
    assert_select "figure figcaption", text: "Units by hour, last 48 hours"
    assert_select "figure figcaption", text: "Units by day, last 30 days"
    assert_select "td.mono", text: "searchEntities"

    get live_developers_key_path(@key)
    assert_response :success
    assert_select "#live-usage", count: 1
    assert_no_match(/<html/, response.body)
  end

  test "the keys list has a 24-hour sparkline per key" do
    sign_in_member
    get developers_keys_path
    assert_response :success
    assert_select "svg.usage-sparkline[aria-label=?]", "Dashboard key: 81,000 units in 24 hours"
  end

  test "usage downloads as CSV, by day, key and operation" do
    sign_in_member
    get developers_usage_path(format: :csv)
    assert_response :success
    rows = CSV.parse(response.body)
    assert_equal %w[day key_id key_name key_prefix operation requests units cache_hits errors_4xx errors_5xx throttled], rows.first
    assert_equal [ (Time.current.utc.to_date - 1).iso8601, "key_#{@key.id}", "Dashboard key", @key.token_prefix, "searchEntities", "300", "900" ], rows[1].first(7)
    assert_equal 3, rows.size
  end

  test "another account's key and usage stay out of reach" do
    post user_session_path, params: { email: users(:admin).email, password: "password123" }
    get live_developers_key_path(@key)
    assert_response :not_found
  end

  test "admins see top consumers with anomaly flags and each account's usage" do
    sign_in_admin
    get admin_developers_root_path
    assert_response :success
    assert_select "h2", text: "Top consumers and anomaly flags"
    assert_select "td.mono", text: "#{@key.token_prefix}…"
    assert_select ".badge", text: "10× spike"
    assert_select ".badge", text: "Near quota"
    assert_select "figure figcaption", text: "All accounts: units by day, last 30 days"

    Usage::Reconciliation.create!(account: @account, day: Date.current - 1, rollup_units: 1_000, edge_units: 1_010, drift: 0.0099, alerted: true, checked_at: Time.current)
    get admin_developers_root_path
    assert_select "h2", text: "Reconciliation drift"
    assert_select ".badge", text: "Edge drift"

    get admin_developers_account_path(@account)
    assert_response :success
    assert_select "figure figcaption", text: "Units by day, last 30 days"
  end
end
