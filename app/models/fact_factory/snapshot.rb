module FactFactory
  # registry_snapshots in fact-factory's schema (db/fact_factory/schema.sql).
  class Snapshot < FactFactoryRecord
    self.table_name = FactFactoryRecord.table("registry_snapshots")
    self.primary_key = "name"
  end
end
