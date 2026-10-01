module FactFactory
  # registry_revisions in fact-factory's schema (db/fact_factory/schema.sql).
  class Revision < FactFactoryRecord
    self.table_name = FactFactoryRecord.table("registry_revisions")
    self.primary_key = "id"
  end
end
