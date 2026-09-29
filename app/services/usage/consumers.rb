module Usage
  # Staff views of usage (design §4.5 and §8.2): the top consumers by units
  # and 429s, with anomaly flags, and who called an operation (for
  # deprecation notices, §9).
  class Consumers
    # A key using 10 times its usual daily units, above a floor.
    SPIKE_FACTOR = 10
    SPIKE_MIN_UNITS = 1_000
    # With no usage in the baseline week, a key must reach this to be flagged.
    NEW_KEY_MIN_UNITS = 10_000
    THROTTLED_SHARE = 0.10
    ERROR_SHARE = 0.5
    MIN_REQUESTS = 100
    BASELINE_DAYS = 7

    Row = Data.define(:account, :api_key, :units, :requests, :errors_4xx, :errors_5xx, :throttled, :baseline, :quota_percent, :flags)

    def initialize(now: Time.current)
      @now = now.utc
    end

    # Top keys (OAuth usage has no key) by units over the last 24 hours, from
    # usage_hourly, with their flags.
    def top(limit: 25)
      since = @now.beginning_of_hour - 23.hours
      rows = Hourly.where(hour_start: since..).group(:account_id, :api_key_id)
        .order(Arel.sql("sum(units) DESC")).limit(limit)
        .pluck(:account_id, :api_key_id, Arel.sql("sum(units)"), Arel.sql("sum(requests)"), Arel.sql("sum(errors_4xx)"),
          Arel.sql("sum(errors_5xx)"), Arel.sql("sum(throttled)"))
      return [] if rows.empty?

      accounts = Account.where(id: rows.map(&:first)).index_by(&:id)
      keys = ApiKey.where(id: rows.filter_map { |r| r[1] }).index_by(&:id)
      baselines = baseline(rows.map { |r| [ r[0], r[1] ] })
      drifted = Reconciliation.drifted.where(day: (@now.to_date - 7)..).distinct.pluck(:account_id).to_set
      quotas = {}
      rows.filter_map do |account_id, key_id, units, requests, e4, e5, throttled|
        account = accounts[account_id] or next
        quota = quotas[account_id] ||= Quota.new(account, now: @now)
        base = baselines.fetch([ account_id, key_id ], 0.0)
        row = { units: units.to_i, requests: requests.to_i, errors_4xx: e4.to_i, errors_5xx: e5.to_i, throttled: throttled.to_i }
        Row.new(account:, api_key: key_id && keys[key_id], **row, baseline: base.round, quota_percent: quota.percent&.round(1),
          flags: flags(row, base, quota, drifted.include?(account_id)))
      end
    end

    # Accounts that called `operation` in the last `days` (usage_daily by operation).
    def callers(operation, days: 30)
      Account.where(id: Daily.where(operation:, day: (@now.to_date - days)..).distinct.select(:account_id))
    end

    private

    # {[account_id, key_id] => average daily units} over the BASELINE_DAYS
    # full days before today.
    def baseline(groups)
      first = @now.to_date - BASELINE_DAYS
      sums = Daily.where(day: first...@now.to_date, account_id: groups.map(&:first).uniq).group(:account_id, :api_key_id).sum(:units)
      sums.transform_values { |units| units.to_f / BASELINE_DAYS }
    end

    def flags(row, base, quota, drifted)
      flags = []
      if base.zero?
        flags << :spike if row[:units] >= NEW_KEY_MIN_UNITS
      elsif row[:units] >= SPIKE_MIN_UNITS && row[:units] >= base * SPIKE_FACTOR
        flags << :spike
      end
      if row[:requests] >= MIN_REQUESTS
        flags << :throttled if row[:throttled] >= row[:requests] * THROTTLED_SHARE
        flags << :errors if row[:errors_4xx] >= row[:requests] * ERROR_SHARE
      end
      pct = quota.percent
      flags << :over_quota if pct && pct >= 100
      flags << :near_quota if pct && pct >= 80 && pct < 100
      flags << :drift if drifted
      flags
    end
  end
end
