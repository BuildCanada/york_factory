class Warehouse::MeasureFact < Warehouse::Record
  self.table_name = "warehouse.measure_facts"
  self.primary_key = :canonical_observation_id

  belongs_to :measure
  belongs_to :document, class_name: "Warehouse::KpiDocument"
  belongs_to :canonical_observation,
    class_name: "Warehouse::CanonicalObservation",
    foreign_key: :canonical_observation_id
  belongs_to :extracted_observation,
    class_name: "Warehouse::ExtractedObservation",
    foreign_key: :extracted_observation_id

  def readonly?
    true
  end
end
