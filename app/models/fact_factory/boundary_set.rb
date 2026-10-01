module FactFactory
  # elections_boundary_sets in fact-factory's schema: elections data, current state, not versioned by revision.
  class BoundarySet < FactFactoryRecord
    self.table_name = FactFactoryRecord.table("elections_boundary_sets")
    self.primary_key = "id"
  end
end
