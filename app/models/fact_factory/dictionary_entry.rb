module FactFactory
  # api.dictionary in fact-factory's read model (serve/api_schema.sql): the
  # data dictionary a release was built with, one row per definition or asset.
  class DictionaryEntry < FactFactoryRecord
    self.table_name = "api.dictionary"
    self.primary_key = nil
  end
end
