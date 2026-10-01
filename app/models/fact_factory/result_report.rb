module FactFactory
  # elections_result_reports in fact-factory's schema: elections data, current state, not versioned by revision.
  class ResultReport < FactFactoryRecord
    self.table_name = FactFactoryRecord.table("elections_result_reports")
    self.primary_key = "id"
  end
end
