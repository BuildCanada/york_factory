module FactFactory
  # api.entity_names in fact-factory's read model (serve/api_schema.sql).
  class EntityName < FactFactoryRecord
    self.table_name = "api.entity_names"
    self.primary_key = nil
  end
end
