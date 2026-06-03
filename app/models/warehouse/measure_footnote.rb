class Warehouse::MeasureFootnote < Warehouse::Record
  self.table_name = "warehouse.measure_footnotes"
  # Composite PK — no synthetic id column.
  self.primary_key = nil

  belongs_to :measure
  belongs_to :source_footnote, class_name: "Warehouse::SourceFootnote"
end
