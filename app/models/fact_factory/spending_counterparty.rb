module FactFactory
  # api.spending_counterparties in fact-factory's read model (serve/api_schema.sql).
  class SpendingCounterparty < FactFactoryRecord
    self.table_name = "api.spending_counterparties"
    self.primary_key = nil
  end
end
