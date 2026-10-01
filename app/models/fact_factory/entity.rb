module FactFactory
  # entities in fact-factory's schema (db/fact_factory/schema.sql).
  class Entity < FactFactoryRecord
    self.table_name = FactFactoryRecord.table("entities")
    self.primary_key = "row_id"
    # `attributes` is an Active Record method; read the column as row["attributes"].
    self.ignored_columns = %w[attributes]
  end
end
