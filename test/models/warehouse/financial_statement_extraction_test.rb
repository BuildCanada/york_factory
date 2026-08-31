require "test_helper"

class Warehouse::FinancialStatementExtractionTest < ActiveSupport::TestCase
  test "normalizes saved verification checks for API and audit artifacts" do
    checks = Warehouse::FinancialStatementExtraction.verification_checks([
      { "id" => "source_identity", "status" => "pass", "detail" => "source matched", "ignored" => true },
      { id: "line_sum:revenue", status: "fail", detail: "totals differ" }
    ])

    assert_equal [
      { id: "source_identity", status: "pass", detail: "source matched" },
      { id: "line_sum:revenue", status: "fail", detail: "totals differ" }
    ], checks
  end

  class UnsupportedTestPipeline
    PARSER_VERSION = "unsupported-test-v1"
    Unsupported = Class.new(StandardError)

    def self.applicable?(**) = true
    def initialize(**) = nil
    def run = raise(Unsupported, "layout is not supported")
  end

  class UnsupportedTestProcessor < Warehouse::FinancialStatementExtraction::QuebecFormProcessor
    private

    def pipeline_class = UnsupportedTestPipeline
  end

  setup do
    @release = Warehouse::InstitutionRelease.create!(
      version: "2026-08-27", effective_on: Date.new(2026, 8, 27), schema_version: "1.0",
      published_at: Time.utc(2026, 8, 27), geography_vintage: 2021, attribution: "Test"
    )
    source = Warehouse::InstitutionSource.create!(
      institution_release: @release, canonical_id: "ca/sources/test",
      publisher_name: "Test", title_en: "Test", url: "https://example.test/source",
      retrieved_at: @release.published_at, languages: [ "en" ]
    )
    @institution = Warehouse::Institution.create!(
      institution_release: @release, institution_source: source, canonical_id: "ca/on/example",
      name_en: "Example", institution_type: "government", government_level: "municipal", status: "active"
    )
    @document = Warehouse::InstitutionDocument.create!(
      institution_release: @release, institution: @institution, institution_source: source,
      canonical_id: "ca/on/example/documents/financial-statements/2025/general",
      document_type: "financial-statements", document_variant: "general"
    )
    @asset = Warehouse::InstitutionDocumentAsset.create!(
      institution_release: @release, institution_document: @document, content_sha256: "a" * 64,
      asset_role: "final", preferred: true, download_url: "https://example.test/statement.pdf",
      retrieved_at: @release.published_at, archive_path: "sha256/aa/#{'a' * 64}.pdf",
      mime_type: "application/pdf", byte_size: 1, rights_status: "metadata_only"
    )
  end

  test "reviewed extractions cannot be rerun in place" do
    extraction = Warehouse::FinancialStatementExtraction.create!(
      institution_release: @release,
      institution_canonical_id: @institution.canonical_id,
      document_canonical_id: @document.canonical_id,
      asset_sha256: @asset.content_sha256,
      fiscal_year_end: Date.new(2025, 12, 31),
      extractor_version: "test-v1",
      status: "extracted", check_results: verification_checks
    )
    extraction.approve!(reviewer: "reviewer")

    error = assert_raises(ArgumentError) do
      extraction.extractor.extract(pdf_path: "missing.pdf", institution_name: "Example")
    end
    assert_includes error.message, "immutable"
    assert_equal "approved", extraction.reload.status
  end

  test "source asset and institution must belong to the extraction release document" do
    extraction = Warehouse::FinancialStatementExtraction.new(
      institution_release: @release, institution_canonical_id: "ca/on/different",
      document_canonical_id: @document.canonical_id, asset_sha256: "b" * 64,
      fiscal_year_end: Date.new(2025, 12, 31), extractor_version: "test-v1", status: "extracted"
    )

    refute extraction.valid?
    assert_includes extraction.errors[:institution_canonical_id],
      "must identify the release document's reporting institution"
    assert_includes extraction.errors[:asset_sha256],
      "must identify an archived asset on the release document"
  end

  test "fiscal year must match the canonical source document year" do
    extraction = Warehouse::FinancialStatementExtraction.new(
      institution_release: @release, institution_canonical_id: @institution.canonical_id,
      document_canonical_id: @document.canonical_id, asset_sha256: @asset.content_sha256,
      fiscal_year_end: Date.new(2024, 12, 31), extractor_version: "test-v1", status: "extracted"
    )

    refute extraction.valid?
    assert_includes extraction.errors[:fiscal_year_end],
      "year must match the source document canonical ID"
  end

  test "archive processor is idempotent for an existing reviewed detail extraction" do
    extraction = Warehouse::FinancialStatementExtraction.create!(
      institution_release: @release, institution_canonical_id: @institution.canonical_id,
      document_canonical_id: @document.canonical_id, asset_sha256: @asset.content_sha256,
      fiscal_year_end: Date.new(2025, 12, 31),
      extractor_version: Warehouse::FinancialStatementExtraction::DetailedPipeline::EXTRACTOR_VERSION,
      status: "extracted", check_results: verification_checks
    )
    extraction.approve!(reviewer: "reviewer")
    candidate = Warehouse::FinancialStatementExtraction::CandidateSet::Candidate.new(
      document_id: @document.id, institution_canonical_id: @institution.canonical_id,
      institution_name: @institution.name_en, document_canonical_id: @document.canonical_id,
      asset_sha256: @asset.content_sha256, fiscal_year_end: Date.new(2025, 12, 31),
      pdf_path: Pathname("missing-but-unneeded.pdf"), population: nil
    )

    result = Warehouse::FinancialStatementExtraction::Processor.new(release: @release).call(candidate)

    assert_equal "skipped", result.status
    assert_equal extraction.id, result.extraction_id
  end

  test "review rerun saves details without promoting a headline that still needs review" do
    headline = extraction_for(
      Warehouse::FinancialStatementExtraction::Pipeline::EXTRACTOR_VERSION,
      status: "needs_review"
    )
    detailed = extraction_for(
      Warehouse::FinancialStatementExtraction::DetailedPipeline::EXTRACTOR_VERSION,
      status: "needs_review"
    )
    pdf_path = Pathname(Dir.mktmpdir).join("statement.pdf")
    pdf_path.write("source")
    candidate = candidate(pdf_path:)
    processor = Warehouse::FinancialStatementExtraction::Processor.new(
      release: @release, rerun: "review"
    )
    headline_called = false
    detailed_called = false

    processor.stub(:run_headline, ->(_candidate, extraction) { headline_called = true; extraction }) do
      processor.stub(:run_detailed, ->(*) { detailed_called = true; detailed }) do
        result = processor.call(candidate)

        assert_equal "needs_review", result.status
        assert_equal "detailed", result.stage
        assert_equal detailed.id, result.extraction_id
      end
    end
    assert headline_called
    assert detailed_called
    assert_equal "needs_review", detailed.reload.status
  ensure
    FileUtils.remove_entry(pdf_path.dirname) if pdf_path&.dirname&.directory?
  end

  test "deterministic unsupported outcomes persist a failed check ledger" do
    pdf_path = Pathname(Dir.mktmpdir).join("statement.pdf")
    pdf_path.write("source")

    result = UnsupportedTestProcessor.new(release: @release).call(candidate(pdf_path:))
    extraction = @release.financial_statement_extractions.find_by!(
      asset_sha256: @asset.content_sha256,
      extractor_version: Warehouse::FinancialStatementExtraction::DetailedPipeline::EXTRACTOR_VERSION
    )

    assert_equal "unsupported", result.status
    assert_equal "failed", extraction.status
    assert_equal "deterministic_parser", extraction.check_results.sole.fetch("id")
    assert_equal "fail", extraction.check_results.sole.fetch("status")
    assert_equal "unsupported", extraction.llm_response_snapshot.fetch("outcome")
  ensure
    FileUtils.remove_entry(pdf_path.dirname) if pdf_path&.dirname&.directory?
  end

  test "approval requires saved verification results" do
    extraction = Warehouse::FinancialStatementExtraction.new(
      institution_release: @release, institution_canonical_id: @institution.canonical_id,
      document_canonical_id: @document.canonical_id, asset_sha256: @asset.content_sha256,
      fiscal_year_end: Date.new(2025, 12, 31), extractor_version: "test-v1", status: "extracted"
    )

    error = assert_raises(ArgumentError) { extraction.approve!(reviewer: "reviewer") }

    assert_includes error.message, "verification check results"
    assert_equal "extracted", extraction.status
  end

  test "all completed statuses require saved verification results" do
    extraction = Warehouse::FinancialStatementExtraction.new(
      institution_release: @release, institution_canonical_id: @institution.canonical_id,
      document_canonical_id: @document.canonical_id, asset_sha256: @asset.content_sha256,
      fiscal_year_end: Date.new(2025, 12, 31), extractor_version: "test-v1", status: "failed"
    )

    refute extraction.valid?
    assert_includes extraction.errors[:check_results], "must be saved for a completed extraction"
  end

  test "extraction exceptions persist a failed check ledger" do
    extraction = extraction_for(
      Warehouse::FinancialStatementExtraction::DetailedPipeline::EXTRACTOR_VERSION,
      status: "extracting"
    )
    error = RubyLLM::BadRequestError.new("invalid request")

    extraction.extractor.send(:record_failure, error, stage: "detailed_extraction")

    extraction.reload
    assert_equal "failed", extraction.status
    assert_equal "detailed_extraction", extraction.check_results.sole.fetch("id")
    assert_equal "fail", extraction.check_results.sole.fetch("status")
    assert_includes extraction.check_results.sole.fetch("detail"), "invalid request"
  end

  test "direct approval requires review provenance" do
    extraction = Warehouse::FinancialStatementExtraction.create!(
      institution_release: @release, institution_canonical_id: @institution.canonical_id,
      document_canonical_id: @document.canonical_id, asset_sha256: @asset.content_sha256,
      fiscal_year_end: Date.new(2025, 12, 31), extractor_version: "test-v1",
      status: "extracted", check_results: verification_checks
    )

    error = assert_raises(ActiveRecord::RecordInvalid) { extraction.update!(status: "approved") }

    assert_includes error.record.errors[:reviewed_at], "and reviewer must be saved before approval"
    assert_equal "extracted", extraction.reload.status
  end

  private

  def extraction_for(version, status:)
    Warehouse::FinancialStatementExtraction.create!(
      institution_release: @release, institution_canonical_id: @institution.canonical_id,
      document_canonical_id: @document.canonical_id, asset_sha256: @asset.content_sha256,
      fiscal_year_end: Date.new(2025, 12, 31), extractor_version: version, status:,
      check_results: status.in?(%w[extracted needs_review approved rejected failed]) ? verification_checks : []
    )
  end

  def candidate(pdf_path:)
    Warehouse::FinancialStatementExtraction::CandidateSet::Candidate.new(
      document_id: @document.id, institution_canonical_id: @institution.canonical_id,
      institution_name: @institution.name_en, document_canonical_id: @document.canonical_id,
      asset_sha256: @asset.content_sha256, fiscal_year_end: Date.new(2025, 12, 31),
      pdf_path:, population: nil
    )
  end

  def verification_checks
    [ { id: "source_identity", status: "pass", detail: "source hash matches" } ]
  end
end
