module FactFactory
  # api.captures in fact-factory's read model (serve/api_schema.sql): one
  # retained source capture a served spending row cites. Immutable.
  class Capture < FactFactoryRecord
    self.table_name = "api.captures"
    self.primary_key = "sha256"
  end
end
