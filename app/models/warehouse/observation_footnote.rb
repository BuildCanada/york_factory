class Warehouse::ObservationFootnote < Warehouse::Record
  self.table_name = "warehouse.observation_footnotes"
  # Composite PK — no synthetic id column.
  self.primary_key = nil

  belongs_to :extracted_observation, class_name: "Warehouse::ExtractedObservation"
  belongs_to :source_footnote,        class_name: "Warehouse::SourceFootnote"
end
