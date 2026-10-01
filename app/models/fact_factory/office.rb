module FactFactory
  # elections_offices in fact-factory's schema: elections data, current state, not versioned by revision.
  class Office < FactFactoryRecord
    self.table_name = FactFactoryRecord.table("elections_offices")
    self.primary_key = "id"
  end
end
