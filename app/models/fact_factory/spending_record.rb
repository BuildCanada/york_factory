module FactFactory
  # spending_records in fact-factory's schema (db/fact_factory/schema.sql).
  class SpendingRecord < FactFactoryRecord
    self.table_name = FactFactoryRecord.table("spending_records")
    self.primary_key = nil
  end
end
