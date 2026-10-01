module FactFactory
  # elections_results in fact-factory's schema: elections data, current state, not versioned by revision.
  class ElectionResult < FactFactoryRecord
    self.table_name = FactFactoryRecord.table("elections_results")
    self.primary_key = "id"
  end
end
