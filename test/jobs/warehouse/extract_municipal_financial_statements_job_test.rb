require "test_helper"
require "active_job/continuation/test_helper"

class TestMunicipalCandidateSet
  def initialize(candidates) = @candidates = candidates
  def asset_root = Pathname(Dir.tmpdir)

  def each(start: nil)
    return enum_for(__method__, start:) unless block_given?

    @candidates.select { start.nil? || _1.document_id >= start }.each { yield _1 }
  end
end

class TestExtractMunicipalFinancialStatementsJob < Warehouse::ExtractMunicipalFinancialStatementsJob
  cattr_accessor :candidates, default: []
  cattr_accessor :results, default: []
  cattr_accessor :processed_ids, default: []

  private

  def candidate_set(**) = TestMunicipalCandidateSet.new(self.class.candidates)

  def processor(**)
    lambda do |candidate|
      self.class.processed_ids << candidate.document_id
      self.class.results.fetch(candidate.document_id)
    end
  end
end

class Warehouse::ExtractMunicipalFinancialStatementsJobTest < ActiveJob::TestCase
  include ActiveJob::Continuation::TestHelper

  setup do
    @release = Warehouse::InstitutionRelease.create!(
      version: "2026-08-31", effective_on: Date.new(2026, 8, 31), schema_version: "1.0",
      published_at: Time.utc(2026, 8, 31), geography_vintage: 2021, attribution: "Test"
    )
    TestExtractMunicipalFinancialStatementsJob.candidates = [ candidate(10), candidate(20), candidate(30) ]
    TestExtractMunicipalFinancialStatementsJob.results = [ 10, 20, 30 ].to_h do |id|
      [ id, outcome("extracted") ]
    end
    TestExtractMunicipalFinancialStatementsJob.processed_ids = []
  end

  test "resumes from the next stable document id" do
    TestExtractMunicipalFinancialStatementsJob.perform_later(@release.version, province: "on")
    interrupt_job_during_step(
      TestExtractMunicipalFinancialStatementsJob, :extract_statements, cursor: 11
    ) { perform_enqueued_jobs }

    assert_equal [ 10 ], TestExtractMunicipalFinancialStatementsJob.processed_ids
    perform_enqueued_jobs
    assert_equal [ 10, 20, 30 ], TestExtractMunicipalFinancialStatementsJob.processed_ids
  end

  test "one failed statement does not halt the province" do
    TestExtractMunicipalFinancialStatementsJob.results[20] = outcome("failed")

    TestExtractMunicipalFinancialStatementsJob.perform_now(@release.version, province: "on")

    assert_equal [ 10, 20, 30 ], TestExtractMunicipalFinancialStatementsJob.processed_ids
  end

  test "opens the circuit after a sustained failure window" do
    TestExtractMunicipalFinancialStatementsJob.candidates = (1..20).map { candidate(_1) }
    TestExtractMunicipalFinancialStatementsJob.results = (1..20).to_h { [ _1, outcome("failed") ] }

    assert_raises(Warehouse::ExtractMunicipalFinancialStatementsJob::CircuitOpen) do
      TestExtractMunicipalFinancialStatementsJob.perform_now(@release.version, province: "on")
    end
  end

  private

  def candidate(id)
    Warehouse::FinancialStatementExtraction::CandidateSet::Candidate.new(
      document_id: id, institution_canonical_id: "ca/on/example",
      institution_name: "Example", document_canonical_id: "ca/on/example/documents/financial-statements/2025/general",
      asset_sha256: "a" * 64, fiscal_year_end: Date.new(2025, 12, 31),
      pdf_path: Pathname("unused.pdf"), population: 1
    )
  end

  def outcome(status)
    Warehouse::FinancialStatementExtraction::Processor::Outcome.new(
      status:, stage: "test", extraction_id: nil, error: status == "failed" ? "test" : nil
    )
  end
end
