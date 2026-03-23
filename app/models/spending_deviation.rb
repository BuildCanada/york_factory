class SpendingDeviation < ApplicationRecord
  self.table_name = "spending_deviations"

  belongs_to :government_entity

  scope :anomalous, -> { where("ABS(variance_pct) > 20") }
  scope :for_year, ->(year) { where(fiscal_year: year) }

  def readonly?
    true
  end
end
