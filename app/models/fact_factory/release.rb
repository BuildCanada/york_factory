module FactFactory
  # api.releases in fact-factory's read model (serve/api_schema.sql).
  class Release < FactFactoryRecord
    self.table_name = "api.releases"
    self.primary_key = "release_id"
  end
end
