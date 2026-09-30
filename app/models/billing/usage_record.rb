module Billing
  # Units one account used in one period (a UTC day), ready to send to a
  # billing meter (Stripe's `api_units`) with its idempotency key. Written by
  # Billing::UsageRecords from usage_daily; sent by Billing::ReportUsageJob
  # once a reporter exists.
  class UsageRecord < ApplicationRecord
    STATUSES = %w[pending reported skipped].freeze

    belongs_to :account

    validates :status, inclusion: { in: STATUSES }

    scope :pending, -> { where(status: "pending") }

    def self.idempotency_key_for(account, period_start) = "acct_#{account.id}-#{period_start.iso8601}"
  end
end
