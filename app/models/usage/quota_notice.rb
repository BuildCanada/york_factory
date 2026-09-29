module Usage
  # One quota email (80% or 100%) to one account for one month. The unique
  # index on (account_id, period, threshold) makes each one send once.
  class QuotaNotice < ApplicationRecord
    self.table_name = "usage_quota_notices"

    THRESHOLDS = [ 80, 100 ].freeze

    belongs_to :account
  end
end
