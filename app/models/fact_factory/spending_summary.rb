module FactFactory
  # api.spending_summary in fact-factory's read model (serve/api_schema.sql).
  class SpendingSummary < FactFactoryRecord
    self.table_name = "api.spending_summary"
    self.primary_key = nil
  end
end
