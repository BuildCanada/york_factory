module FactFactory
  # elections_candidacies in fact-factory's schema: elections data, current state, not versioned by revision.
  class Candidacy < FactFactoryRecord
    self.table_name = FactFactoryRecord.table("elections_candidacies")
    self.primary_key = "id"
  end
end
