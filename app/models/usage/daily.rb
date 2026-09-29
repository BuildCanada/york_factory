module Usage
  # Units and requests per account, key, operation and UTC day. The billing
  # source (design §6.4), rebuilt from usage_hourly by Usage::Rollup.
  class Daily < ApplicationRecord
    self.table_name = "usage_daily"

    COUNTERS = %i[requests units cache_hits errors_4xx errors_5xx throttled].freeze

    belongs_to :account
    belongs_to :api_key, optional: true

    scope :for_month, ->(time) { where(day: time.utc.to_date.beginning_of_month..time.utc.to_date.end_of_month) }
  end
end
