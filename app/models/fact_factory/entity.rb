module FactFactory
  # api.entities in fact-factory's read model (serve/api_schema.sql).
  class Entity < FactFactoryRecord
    self.table_name = "api.entities"
    self.primary_key = "row_id"
    # `attributes` is an Active Record method; read the column as row["attributes"].
    self.ignored_columns = %w[attributes]
  end
end
