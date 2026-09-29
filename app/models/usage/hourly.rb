module Usage
  # Units and requests per account, key, operation and hour (7 days).
  class Hourly < ApplicationRecord
    self.table_name = "usage_hourly"

    belongs_to :account
    belongs_to :api_key, optional: true
  end
end
