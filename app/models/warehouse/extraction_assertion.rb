class Warehouse::ExtractionAssertion < Warehouse::Record
  self.table_name = "warehouse.extraction_assertions"

  belongs_to :extracted_observation, class_name: "Warehouse::ExtractedObservation"

  validates :assertion_type, :assertion_text, presence: true
  validates :confidence,
    numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 },
    allow_nil: true
end
