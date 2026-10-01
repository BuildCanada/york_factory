module FactFactory
  # entity_identifiers in fact-factory's schema (db/fact_factory/schema.sql).
  class Identifier < FactFactoryRecord
    self.table_name = FactFactoryRecord.table("entity_identifiers")
    self.primary_key = "row_id"
  end
end
