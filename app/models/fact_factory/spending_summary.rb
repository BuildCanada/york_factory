module FactFactory
  # spending_summary in fact-factory's schema (db/fact_factory/schema.sql).
  class SpendingSummary < FactFactoryRecord
    self.table_name = FactFactoryRecord.table("spending_summary")
    self.primary_key = "id"
  end
end
