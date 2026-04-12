class SpendingDeviation < WarehouseRecord

  belongs_to :organization

  scope :anomalous, -> { where("ABS(variance_pct) > 20") }
  scope :for_year, ->(year) { where(fiscal_year: year) }

  def readonly?
    true
  end
end
