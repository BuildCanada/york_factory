module FactFactory
  # api.release_exports in fact-factory's read model (serve/api_schema.sql).
  class ReleaseExport < FactFactoryRecord
    self.table_name = "api.release_exports"
    self.primary_key = nil
  end
end
