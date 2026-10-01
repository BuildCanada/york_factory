module FactFactory
  # elections_candidate_contacts in fact-factory's schema: elections data, current state, not versioned by revision.
  class CandidateContact < FactFactoryRecord
    self.table_name = FactFactoryRecord.table("elections_candidate_contacts")
    self.primary_key = nil
  end
end
