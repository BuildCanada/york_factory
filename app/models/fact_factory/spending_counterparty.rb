module FactFactory
  # spending_counterparties in fact-factory's schema (db/fact_factory/schema.sql).
  class SpendingCounterparty < FactFactoryRecord
    self.table_name = FactFactoryRecord.table("spending_counterparties")
    self.primary_key = "id"
  end
end
