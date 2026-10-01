module FactFactory
  # elections_captures in fact-factory's schema: elections data, current state, not versioned by revision.
  class ElectionsCapture < FactFactoryRecord
    self.table_name = FactFactoryRecord.table("elections_captures")
    self.primary_key = "sha256"
  end
end
