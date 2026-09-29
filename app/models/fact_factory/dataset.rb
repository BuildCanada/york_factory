module FactFactory
  # api.datasets in fact-factory's read model (serve/api_schema.sql): one
  # spending slice or registry table as a release serves it.
  class Dataset < FactFactoryRecord
    self.table_name = "api.datasets"
    self.primary_key = nil
  end
end
