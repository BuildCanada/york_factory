module Usage
  # Emails an account's owners once when this month's units reach 80% of the
  # plan's quota and once at 100% (design §6.2). The usage_quota_notices row
  # is claimed first, under its unique index, so a notice is sent once even
  # when two runs overlap. An account that jumps past 100% gets only the 100%
  # email.
  class QuotaNotices
    def initialize(now: Time.current)
      @now = now.utc
    end

    # Accounts with usage this month; returns the notices sent.
    def run!
      ids = Daily.for_month(@now).distinct.pluck(:account_id)
      Account.where(id: ids).includes(:memberships).filter_map { |account| check(account) }
    end

    def check(account)
      quota = Quota.new(account, now: @now)
      threshold = quota.threshold_reached or return nil
      return nil if QuotaNotice.exists?(account:, period: quota.period, threshold:)

      claimed = QuotaNotice.insert_all(
        [ { account_id: account.id, period: quota.period, threshold:, units: quota.used, quota: quota.quota, sent_at: Time.current } ],
        unique_by: %i[account_id period threshold], returning: %w[id]
      )
      return nil if claimed.rows.empty?

      UsageMailer.with(account:, threshold:, used: quota.used, quota: quota.quota, resets_at: quota.resets_at).quota_warning.deliver_later
      AuditEvent.record!("account.quota_notice", context: AuditEvent::Context.system, account:, subject: account,
        metadata: { threshold:, period: quota.period, units: quota.used, quota: quota.quota })
      threshold
    end
  end
end
