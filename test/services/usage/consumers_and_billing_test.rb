require "test_helper"

class Usage::ConsumersAndBillingTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @key = issue_key(user: users(:member)).api_key
    @account = @key.account
    @quiet = issue_key(user: users(:admin)).api_key
    @now = Time.utc(2026, 9, 20, 12, 30)
  end

  def hour(units, key: @key, at: @now, requests: units, throttled: 0, errors_4xx: 0, operation: "getEntity")
    Usage::Hourly.create!(account: key.account, api_key_id: key.id, operation:, hour_start: at.beginning_of_hour, units:, requests:,
      throttled:, errors_4xx:, rolled_up_at: @now)
  end

  def day(units, key: @key, day: @now.to_date - 1, operation: "getEntity")
    Usage::Daily.create!(account: key.account, api_key_id: key.id, operation:, day:, units:, requests: units, rolled_up_at: @now)
  end

  test "top consumers flag a sudden 10x, many 429s, mostly 4xx and quota" do
    7.times { |i| day(300, day: @now.to_date - 1 - i) }
    hour(3_500, at: @now - 2.hours)
    7.times { |i| day(1_000, key: @quiet, day: @now.to_date - 1 - i) }
    hour(1_200, key: @quiet, requests: 1_200, throttled: 400, errors_4xx: 700)

    rows = Usage::Consumers.new(now: @now).top
    assert_equal [ @key, @quiet ], rows.map(&:api_key)
    spike, steady = rows
    assert_equal 300, spike.baseline
    assert_includes spike.flags, :spike
    refute_includes steady.flags, :spike
    assert_includes steady.flags, :throttled
    assert_includes steady.flags, :errors

    Usage::Daily.create!(account: @account, api_key_id: @key.id, operation: "searchEntities", day: @now.to_date, units: 85_000, rolled_up_at: @now)
    assert_includes Usage::Consumers.new(now: @now).top.first.flags, :near_quota
  end

  test "a key with no history is flagged only past 10,000 units" do
    hour(9_000)
    assert_empty Usage::Consumers.new(now: @now).top.first.flags
    hour(2_000, at: @now - 1.hour)
    assert_equal [ :spike ], Usage::Consumers.new(now: @now).top.first.flags
  end

  test "who called an operation in the last 30 days, for deprecation notices" do
    day(5, operation: "listSpending")
    day(5, key: @quiet, operation: "getEntity")
    day(5, key: @quiet, operation: "listSpending", day: @now.to_date - 40)
    assert_equal [ @account ], Usage::Consumers.new(now: @now).callers("listSpending").to_a
  end

  test "billing records: one per metered account and day, idempotent, never changed once reported" do
    target = @now.to_date - 3
    day(1_200, day: target)
    day(800, day: target, operation: "searchEntities")
    day(50, key: @quiet, day: target)
    @account.update!(plan: "paid")

    records = Billing::UsageRecords.new.build!(day: target)
    assert_equal 1, records.size, "free accounts are not metered"
    record = records.first
    assert_equal [ 2_000, "pending", "api_units", "acct_#{@account.id}-#{target.iso8601}", target + 1 ],
      [ record.units, record.status, record.meter, record.idempotency_key, record.period_end ]

    Usage::Daily.where(account: @account, day: target, operation: "getEntity").update_all(units: 1_300)
    Billing::UsageRecords.new.build!(day: target)
    assert_equal [ 2_100 ], Billing::UsageRecord.pluck(:units), "a late point updates a pending record"

    record.reload.update!(status: "reported", external_id: "evt_1", reported_at: @now)
    Usage::Daily.where(account: @account, day: target, operation: "getEntity").update_all(units: 9_999)
    Billing::UsageRecords.new.build!(day: target)
    assert_equal [ 2_100 ], Billing::UsageRecord.pluck(:units)
  end

  test "the report job sends nothing with the null reporter, and marks what a reporter sends" do
    target = Time.current.utc.to_date - 3
    @account.update!(plan: "paid")
    day(10, day: target)
    Billing::ReportUsageJob.perform_now
    assert_equal [ "pending" ], Billing::UsageRecord.pluck(:status)

    sent = []
    reporter = Object.new
    reporter.define_singleton_method(:report) { |record| sent << record.idempotency_key and "evt_#{record.id}" }
    Billing::Reporter.current = reporter
    Billing::ReportUsageJob.perform_now
    assert_equal [ "reported" ], Billing::UsageRecord.pluck(:status)
    assert_equal 1, sent.size
    Billing::ReportUsageJob.perform_now
    assert_equal 1, sent.size, "a reported record is not sent again"
  ensure
    Billing::Reporter.current = nil
  end

  test "an expired plan override is cleared and the account's keys are pushed to the edge" do
    @account.update!(plan_override: "partner", plan_override_expires_at: 1.minute.ago)
    pushed = []
    Edge::Push.stub(:account, ->(account) { pushed << account.id }) do
      Accounts::ExpirePlanOverridesJob.perform_now
    end
    assert_equal [ @account.id ], pushed
    assert_nil @account.reload.plan_override
    assert_equal "free", @key.reload.lookup_payload[:plan]
    assert AuditEvent.exists?(action: "account.plan_override_expired", account_id: @account.id)
  end
end
