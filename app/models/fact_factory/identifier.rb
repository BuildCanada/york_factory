module FactFactory
  # api.identifiers in fact-factory's read model (serve/api_schema.sql).
  class Identifier < FactFactoryRecord
    self.table_name = "api.identifiers"
    self.primary_key = "row_id"
  end
end
