module FactFactory
  # spending_publications in fact-factory's schema (db/fact_factory/schema.sql).
  class SpendingPublication < FactFactoryRecord
    self.table_name = FactFactoryRecord.table("spending_publications")
    self.primary_key = "id"
  end
end
