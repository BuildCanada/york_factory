module Usage
  # Compares one UTC day's rolled-up units per account (usage_daily) with the
  # edge's AccountDO day totals (Edge::UsageClient; design §6.3: "daily units
  # must match AccountDO within 0.5% or admin is alerted"). Each comparison is
  # kept in usage_reconciliations; drifted ones are mailed to staff and shown
  # on the admin dashboard.
  class Reconcile
    def initialize(edge: Edge::UsageClient.new, now: Time.current)
      @edge = edge
      @now = now.utc
    end

    # Returns the drifted reconciliations, or nil when the edge isn't configured.
    def run!(day: @now.to_date - 1)
      return nil unless @edge.configured?

      rolled = Daily.where(day:).group(:account_id).sum(:units)
      drifted = []
      # Accounts the rollup has for the day, and any whose keys were used that
      # day, in case the edge counted what Analytics Engine lost.
      used = ApiKey.where(last_used_at: day.in_time_zone("UTC").all_day).distinct.pluck(:account_id)
      Account.where(id: rolled.keys | used).find_each do |account|
        edge_days = @edge.account_days(account, month: day.strftime("%Y-%m")) or next
        check = record(account, day, rolled.fetch(account.id, 0), edge_days.fetch(day, 0))
        drifted << check if check.alerted
      end
      UsageMailer.with(reconciliations: drifted).reconcile_drift.deliver_later if drifted.any?
      drifted
    end

    def record(account, day, rollup_units, edge_units)
      base = [ rollup_units, edge_units ].max
      drift = base.zero? ? 0.0 : (rollup_units - edge_units).abs.to_f / base
      check = Reconciliation.find_or_initialize_by(account:, day:)
      check.update!(rollup_units:, edge_units:, drift:, alerted: drift > Reconciliation::TOLERANCE, checked_at: Time.current)
      check
    end
  end
end
