module FactFactory
  # elections_contests in fact-factory's schema: elections data, current state, not versioned by revision.
  class Contest < FactFactoryRecord
    self.table_name = FactFactoryRecord.table("elections_contests")
    self.primary_key = "id"
  end
end
