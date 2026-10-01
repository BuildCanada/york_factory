module FactFactory
  # mention_occurrences in fact-factory's schema (db/fact_factory/schema.sql).
  class Occurrence < FactFactoryRecord
    self.table_name = FactFactoryRecord.table("mention_occurrences")
    self.primary_key = "row_id"
  end
end
