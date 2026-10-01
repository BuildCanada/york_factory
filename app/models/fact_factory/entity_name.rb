module FactFactory
  # entity_names in fact-factory's schema (db/fact_factory/schema.sql).
  class EntityName < FactFactoryRecord
    self.table_name = FactFactoryRecord.table("entity_names")
    self.primary_key = nil
  end
end
