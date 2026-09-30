module FactFactory
  # api.spending_parties in fact-factory's read model (serve/api_schema.sql).
  class SpendingParty < FactFactoryRecord
    self.table_name = "api.spending_parties"
    self.primary_key = "row_id"
  end
end
