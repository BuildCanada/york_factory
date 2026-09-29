require "test_helper"

class Usage::QuotaAndReconcileTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include ActionMailer::TestHelper

  setup do
    @user = users(:member)
    @key = issue_key(user: @user).api_key
    @account = @key.account
    @now = Time.utc(2026, 9, 20, 12)
  end

  def use(units, day: @now.to_date, operation: "getEntity", account: @account, key: @key)
    row = Usage::Daily.find_or_initialize_by(account:, api_key_id: key&.id, operation:, day:)
    row.update!(units: row.units + units, requests: row.requests + units, rolled_up_at: @now)
  end

  test "the quota: used, remaining, percent, forecast and reset" do
    use(40_000)
    use(5_000, day: Date.new(2026, 8, 31))
    quota = Usage::Quota.new(@account, now: @now)
    assert_equal [ 100_000, 40_000, 60_000, 40.0 ], [ quota.quota, quota.used, quota.remaining, quota.percent ]
    assert_equal Time.utc(2026, 10, 1), quota.resets_at
    assert_in_delta 40_000 / 19.5 * 30, quota.forecast, 1
    assert_nil quota.threshold_reached
    @account.update!(plan: "internal")
    assert Usage::Quota.new(@account, now: @now).unlimited?
  end

  test "80% and 100% emails are sent once each, to the owners" do
    notices = Usage::QuotaNotices.new(now: @now)
    use(79_999)
    assert_no_enqueued_emails { notices.run! }

    use(1)
    assert_enqueued_emails(1) { notices.run! }
    assert_no_enqueued_emails { notices.run! }
    assert_no_enqueued_emails { Usage::QuotaNotices.new(now: @now + 1.hour).run! }

    use(20_000)
    assert_enqueued_emails(1) { notices.run! }
    assert_no_enqueued_emails { notices.run! }
    assert_equal [ 80, 100 ], Usage::QuotaNotice.where(account: @account, period: "2026-09").order(:threshold).pluck(:threshold)
    assert_equal 2, AuditEvent.where(action: "account.quota_notice", account_id: @account.id).count

    use(90_000, day: Date.new(2026, 10, 2))
    assert_enqueued_emails(1) { Usage::QuotaNotices.new(now: Time.utc(2026, 10, 2, 12)).run! }
  end

  test "an account that jumps past 100% gets only the 100% email" do
    use(150_000)
    assert_enqueued_emails(1) { Usage::QuotaNotices.new(now: @now).run! }
    assert_equal [ 100 ], Usage::QuotaNotice.pluck(:threshold)
  end

  test "the quota emails say where the account stands" do
    mail = UsageMailer.with(account: @account, threshold: 80, used: 80_123, quota: 100_000, resets_at: Time.utc(2026, 10, 1)).quota_warning
    assert_equal [ @user.email ], mail.to
    assert_equal "You've used 80% of your Build Canada API quota", mail.subject
    assert_includes mail.body.to_s, "80,123 of its 100,000 monthly Build Canada API units (80%)"
    assert_includes mail.body.to_s, "2026-10-01 00:00 UTC"

    mail = UsageMailer.with(account: @account, threshold: 100, used: 100_004, quota: 100_000, resets_at: Time.utc(2026, 10, 1)).quota_warning
    assert_equal "Your Build Canada API quota is used up for this month", mail.subject
    assert_includes mail.body.to_s, "429 quota_exceeded"
  end

  test "reconcile alerts staff on a seeded 1% drift, not on 0.2%" do
    other = issue_key(user: users(:admin)).api_key
    day = @now.to_date - 1
    use(10_000, day:)
    use(10_000, day:, account: other.account, key: other)

    edge = Class.new do
      def initialize(by_account) = @by_account = by_account
      def configured? = true
      def account_days(account, month:) = @by_account.fetch(account.id)
    end.new({ @account.id => { day => 10_100 }, other.account.id => { day => 10_020 } })

    drifted = nil
    assert_enqueued_emails(1) { drifted = Usage::Reconcile.new(edge:, now: @now).run! }
    assert_equal [ @account.id ], drifted.map(&:account_id)
    check = Usage::Reconciliation.find_by!(account: @account, day:)
    assert_in_delta 100.0 / 10_100, check.drift, 1e-9
    refute Usage::Reconciliation.find_by!(account: other.account, day:).alerted

    mail = UsageMailer.with(reconciliations: drifted).reconcile_drift
    assert_equal User.where(role: "superadmin").pluck(:email), mail.to
    assert_includes mail.body.to_s, "rollup 10,000 units, edge 10,100"

    assert_nil Usage::Reconcile.new(edge: Edge::UsageClient.new(url: nil, secret: nil), now: @now).run!
  end
end
