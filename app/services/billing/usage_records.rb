module Billing
  # Writes one Billing::UsageRecord per metered account and UTC day from
  # usage_daily (design §6.4: "Billing::ReportUsageJob sends daily units from
  # usage_daily (idempotent per account and day)"). Rewriting a day updates
  # its pending records, so late points are included until the day is
  # reported; a reported record is never changed.
  class UsageRecords
    # Plans billed by usage. None is sold yet; `paid` is the future plan.
    METERED_PLANS = %w[paid].freeze
    METER = "api_units".freeze

    def self.metered?(account) = METERED_PLANS.include?(account.effective_plan_name)

    # Returns the records written or updated for `day`.
    def build!(day:)
      totals = Usage::Daily.where(day:).group(:account_id).sum(:units)
      Account.where(id: totals.keys).select { |account| self.class.metered?(account) }.filter_map do |account|
        record = UsageRecord.find_or_initialize_by(account:, period_start: day)
        next if record.status == "reported"

        record.assign_attributes(period_end: day + 1, units: totals.fetch(account.id), meter: METER,
          idempotency_key: UsageRecord.idempotency_key_for(account, day))
        record.save! if record.changed?
        record
      end
    end
  end
end
