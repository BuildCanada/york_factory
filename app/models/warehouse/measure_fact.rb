class Warehouse::MeasureFact < Warehouse::Record
  self.primary_key = :citation_id

  belongs_to :measure
  belongs_to :document, class_name: "Warehouse::KpiDocument"
  belongs_to :citation, class_name: "Warehouse::MeasureCitation", foreign_key: :citation_id

  def readonly?
    true
  end
end
