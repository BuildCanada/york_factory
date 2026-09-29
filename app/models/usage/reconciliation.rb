module Usage
  # One day's rolled-up units for an account against the edge's AccountDO
  # (design §6.3: they must match within 0.5%).
  class Reconciliation < ApplicationRecord
    self.table_name = "usage_reconciliations"

    TOLERANCE = 0.005

    belongs_to :account

    scope :drifted, -> { where(alerted: true) }
  end
end
