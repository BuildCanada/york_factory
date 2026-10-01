module FactFactory
  # elections_districts in fact-factory's schema: elections data, current state, not versioned by revision.
  class District < FactFactoryRecord
    self.table_name = FactFactoryRecord.table("elections_districts")
    self.primary_key = "id"
  end
end
