module Usage
  # An account's units this UTC month against its plan's monthly quota
  # (design §6.2). `used` is the rollup's (usage_daily, about a minute behind);
  # the edge's AccountDO enforces the quota itself.
  class Quota
    attr_reader :account, :quota, :used, :period

    def initialize(account, now: Time.current)
      @account = account
      @now = now.utc
      @period = @now.strftime("%Y-%m")
      @quota = account.plan_definition.monthly
      @used = account.monthly_units_used(now: @now)
    end

    def unlimited? = quota.nil?

    def remaining = unlimited? ? nil : [ quota - used, 0 ].max

    def percent = unlimited? || quota.zero? ? nil : (used * 100.0 / quota)

    def resets_at = @now.beginning_of_month.next_month

    # Units a day at this month's pace so far, projected to the month's end.
    def forecast
      elapsed = (@now - @now.beginning_of_month) / 1.day
      return used if elapsed < 1

      (used / elapsed * (resets_at - @now.beginning_of_month) / 1.day).round
    end

    # The highest notice threshold (80 or 100) this month's use has reached.
    def threshold_reached = unlimited? ? nil : QuotaNotice::THRESHOLDS.select { |t| used * 100 >= quota * t }.max
  end
end
