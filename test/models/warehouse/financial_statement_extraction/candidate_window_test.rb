require "test_helper"

class Warehouse::FinancialStatementExtraction::CandidateWindowTest < ActiveSupport::TestCase
  Candidate = Data.define(:document_id)

  test "includes the document before the boundary and stops at the boundary" do
    window = Warehouse::FinancialStatementExtraction::CandidateWindow.new(
      start: 9251, stop_before: 9252
    )

    refute window.before_start?(Candidate.new(document_id: 9251))
    refute window.at_or_after_stop?(Candidate.new(document_id: 9251))
    assert window.at_or_after_stop?(Candidate.new(document_id: 9252))
  end

  test "supports explicit canary inclusion and remainder exclusion" do
    canary = Warehouse::FinancialStatementExtraction::CandidateWindow.new(
      document_ids: [ 10, 12 ]
    )
    remainder = Warehouse::FinancialStatementExtraction::CandidateWindow.new(
      excluded_document_ids: [ 10, 12 ]
    )

    assert canary.selected?(Candidate.new(document_id: 10))
    refute canary.selected?(Candidate.new(document_id: 11))
    assert remainder.excluded?(Candidate.new(document_id: 12))
    refute remainder.excluded?(Candidate.new(document_id: 13))
  end
end
