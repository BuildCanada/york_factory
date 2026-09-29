module FactFactory
  # api.relationships in fact-factory's read model (serve/api_schema.sql).
  class Relationship < FactFactoryRecord
    self.table_name = "api.relationships"
    self.primary_key = "row_id"
    # `attributes` is an Active Record method; read the column as row["attributes"].
    self.ignored_columns = %w[attributes]
  end
end
