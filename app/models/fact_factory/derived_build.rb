module FactFactory
  # derived_builds in fact-factory's schema (db/fact_factory/schema.sql).
  class DerivedBuild < FactFactoryRecord
    self.table_name = FactFactoryRecord.table("derived_builds")
    self.primary_key = "revision_id"
  end
end
