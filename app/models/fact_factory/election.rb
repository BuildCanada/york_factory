module FactFactory
  # elections_elections in fact-factory's schema: elections data, current state, not versioned by revision.
  class Election < FactFactoryRecord
    self.table_name = FactFactoryRecord.table("elections_elections")
    self.primary_key = "id"
  end
end
