module FactFactory
  # api.spending_records in fact-factory's read model (serve/api_schema.sql).
  class SpendingRecord < FactFactoryRecord
    self.table_name = "api.spending_records"
    self.primary_key = nil
  end
end
