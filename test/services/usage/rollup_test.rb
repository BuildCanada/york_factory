require "test_helper"

class Usage::RollupTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include ActionMailer::TestHelper

  setup do
    @ae = FakeAnalyticsEngine.new
    @issued = issue_key(scopes: %w[read:public usage:read])
    @key = @issued.api_key
    @account = @key.account
    @now = Time.utc(2026, 9, 29, 12, 30)
  end

  def rollup(window: 48.hours, now: @now) = Usage::Rollup.new(client: @ae.client, now:).run!(window:)

  test "rolls points up per account, key, operation and hour, and per day" do
    @ae.write(account_id: @account.id, key_id: @key.id, at: @now - 10.minutes, count: 3)
    @ae.write(account_id: @account.id, key_id: @key.id, operation: "searchEntities", units: 3, at: @now - 10.minutes, cache: "hit")
    @ae.write(account_id: @account.id, key_id: @key.id, at: @now - 3.hours, status: 429, units: 0)
    @ae.write(account_id: @account.id, key_id: @key.id, at: @now - 13.hours, status: 404)
    @ae.write(account_id: @account.id, key_id: nil, operation: "getEntity", at: @now - 5.minutes, units: 1)

    result = rollup
    assert_equal 5, result.hourly_rows

    hour = Usage::Hourly.find_by!(api_key_id: @key.id, operation: "getEntity", hour_start: @now.beginning_of_hour)
    assert_equal [ 3, 3, 0 ], [ hour.requests, hour.units, hour.cache_hits ]
    assert_equal 1, Usage::Hourly.find_by!(api_key_id: @key.id, hour_start: (@now - 3.hours).beginning_of_hour).throttled
    assert Usage::Hourly.exists?(api_key_id: nil, account_id: @account.id), "OAuth usage: an account and no key"

    today = Usage::Daily.where(account: @account, day: @now.to_date)
    assert_equal({ "getEntity" => 3, "searchEntities" => 3 }, today.where(api_key_id: @key.id).group(:operation).sum(:units))
    assert_equal [ 1, 1 ], [ today.sum(:errors_4xx), today.sum(:throttled) ], "a 429 is a 4xx"
    assert_equal 1, Usage::Daily.where(account: @account, day: @now.to_date - 1).sum(:errors_4xx), "13 hours ago is yesterday"
    assert_equal 8, @account.monthly_units_used(now: @now)
    assert_equal 1, Usage::RollupRun.count
  end

  test "running twice gives the same rows" do
    @ae.write(account_id: @account.id, key_id: @key.id, at: @now - 1.hour, count: 5, units: 2)
    rollup
    first = Usage::Daily.order(:id).pluck(:account_id, :api_key_id, :operation, :day, :units)
    rollup
    rollup(window: 2.hours)
    assert_equal first, Usage::Daily.order(:id).pluck(:account_id, :api_key_id, :operation, :day, :units)
    assert_equal 10, Usage::Daily.sum(:units)
    assert_equal 10, Usage::Hourly.sum(:units)
  end

  test "a point that arrives late is counted by the next run whose window covers its hour" do
    @ae.write(account_id: @account.id, key_id: @key.id, at: @now - 20.hours, units: 4)
    rollup
    assert_equal 4, Usage::Daily.sum(:units)

    # Written to Analytics Engine after the first run, for an hour already rolled up.
    @ae.write(account_id: @account.id, key_id: @key.id, at: @now - 20.hours, units: 6)
    rollup(window: 2.hours, now: @now + 1.minute)
    assert_equal 4, Usage::Daily.sum(:units), "the recent window doesn't reach back 20 hours"

    rollup(window: 48.hours, now: @now + 1.hour)
    assert_equal 10, Usage::Daily.sum(:units)
    assert_equal 10, Usage::Hourly.where(hour_start: (@now - 20.hours).beginning_of_hour).sum(:units)
  end

  test "a day keeps the hours outside a short window" do
    @ae.write(account_id: @account.id, key_id: @key.id, at: @now.beginning_of_day + 1.hour, units: 7)
    rollup
    @ae.write(account_id: @account.id, key_id: @key.id, at: @now - 5.minutes, units: 1)
    rollup(window: 2.hours)
    assert_equal 8, Usage::Daily.where(day: @now.to_date).sum(:units), "rebuilt from every hourly row of the day"
  end

  test "unknown accounts and malformed rows are skipped; hourly rows go after 7 days" do
    @ae.write(account_id: 999_999_999, key_id: 1, at: @now - 1.hour)
    @ae.write(account_id: "", at: @now - 1.hour)
    @ae.write(account_id: @account.id, key_id: @key.id, operation: "bad op; DROP", at: @now - 1.hour)
    result = rollup
    assert_equal 1, result.skipped
    assert_equal [ "unknown" ], Usage::Hourly.pluck(:operation)

    Usage::Hourly.create!(account: @account, api_key_id: @key.id, operation: "getEntity", hour_start: @now - 8.days, units: 1, rolled_up_at: @now)
    rollup
    refute Usage::Hourly.where(hour_start: ...(@now - 7.days)).exists?
  end

  test "sends the Analytics Engine SQL with the token, and does nothing unconfigured" do
    rollup
    query = @ae.queries.last
    assert_equal "Bearer cf-token", query[:headers]["authorization"]
    assert_includes query[:url], "/accounts/cf-account/analytics_engine/sql"
    assert_includes query[:sql], "FROM data_api_requests"
    assert_includes query[:sql], "toDateTime('2026-09-27 12:00:00')"

    assert_nil Usage::Rollup.new(client: AnalyticsEngineClient.new(account_id: nil, api_token: nil), now: @now).run!
    @ae.fail_with = 500
    assert_raises(AnalyticsEngineClient::Error) { rollup }
  end

  test "the job rolls up and sends quota notices" do
    AnalyticsEngineClient.stub(:new, @ae.client) do
      @ae.write(account_id: @account.id, key_id: @key.id, at: Time.current - 1.minute, units: 85_000)
      assert_enqueued_emails 1 do
        Usage::RollupJob.perform_now(2)
      end
    end
    assert_equal [ 80 ], Usage::QuotaNotice.where(account: @account).pluck(:threshold)
  end
end
