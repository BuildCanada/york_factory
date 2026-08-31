require "test_helper"

class AuditMunicipalFinancialExtractionCoverageTest < ActiveSupport::TestCase
  setup do
    @release = Warehouse::InstitutionRelease.create!(
      version: "2026-08-30", effective_on: Date.new(2026, 8, 30),
      schema_version: "1.0", published_at: Time.utc(2026, 8, 30), geography_vintage: 2021,
      attribution: "Test"
    )
    @source = Warehouse::InstitutionSource.create!(
      institution_release: @release, canonical_id: "ca/sources/coverage-audit-test",
      publisher_name: "Test", title_en: "Test", url: "https://example.test/source",
      retrieved_at: @release.published_at, languages: [ "en" ]
    )
  end

  test "classifies shared assets and headline gates without duplicating facts" do
    predicted_owner = create_document("ca/nb/predicted-owner", 2025, "a" * 64)
    persisted_owner = create_document("ca/nb/persisted-owner", 2025, "a" * 64)
    approved = create_detailed_extraction(persisted_owner, "a" * 64)

    unattempted_owner = create_document("ca/nb/unattempted-owner", 2024, "b" * 64)
    unattempted_alias = create_document("ca/nb/unattempted-alias", 2024, "b" * 64)
    headline_document = create_document("ca/nb/headline-gate", 2023, "c" * 64)
    create_failed_headline_extraction(headline_document, "c" * 64)

    payload = Warehouse::FinancialStatementExtraction::CoverageAudit.new(
      release: @release, provinces: [ "nb" ]
    ).payload
    records = payload.fetch(:records).index_by { _1.fetch(:document_canonical_id) }

    persisted_alias = records.fetch(predicted_owner.canonical_id)
    assert_equal "shared_asset", persisted_alias.fetch(:status)
    assert_equal "shared_asset", persisted_alias.fetch(:extraction_stage)
    assert_equal approved.id, persisted_alias.fetch(:extraction_id)
    assert_equal persisted_owner.canonical_id,
      persisted_alias.fetch(:shared_with_document_canonical_id)
    assert_equal "ca/nb/persisted-owner",
      persisted_alias.fetch(:shared_with_institution_canonical_id)
    assert_equal "approved", persisted_alias.fetch(:shared_extraction_status)
    assert_equal 1, persisted_alias.dig(:verification, :total)
    assert_equal 0, persisted_alias.fetch(:fact_count)
    assert_equal 0, persisted_alias.fetch(:line_item_count)

    owner_record = records.fetch(persisted_owner.canonical_id)
    assert_equal "approved", owner_record.fetch(:status)
    assert_equal 1, owner_record.fetch(:fact_count)
    assert_equal 1, owner_record.fetch(:line_item_count)

    predicted_alias = records.fetch(unattempted_alias.canonical_id)
    assert_equal "shared_asset", predicted_alias.fetch(:status)
    assert_nil predicted_alias.fetch(:extraction_id)
    assert_equal unattempted_owner.canonical_id,
      predicted_alias.fetch(:shared_with_document_canonical_id)
    assert_equal 0, predicted_alias.dig(:verification, :total)
    assert_equal "unattempted", records.fetch(unattempted_owner.canonical_id).fetch(:status)

    headline_gate = records.fetch(headline_document.canonical_id)
    assert_equal "failed_headline_gate", headline_gate.fetch(:status)
    assert_equal "headline_gate", headline_gate.fetch(:extraction_stage)
    assert_equal 1, headline_gate.dig(:verification, :total)
    assert_equal "fail", headline_gate.dig(:verification, :checks, 0, :status)

    totals = payload.fetch(:totals)
    assert_equal 5, totals.fetch(:preferred_asset_count)
    assert_equal({ "approved" => 1, "shared_asset" => 2, "unattempted" => 1,
      "failed_headline_gate" => 1 }, totals.fetch(:status_counts))
    assert_equal 4, totals.dig(:reconciliation, :classified_asset_count)
    assert_equal 1, totals.dig(:reconciliation, :unclassified_asset_count)
    assert_equal totals.fetch(:preferred_asset_count),
      totals.dig(:reconciliation, :classified_asset_count) +
        totals.dig(:reconciliation, :unclassified_asset_count)
    assert_equal 0, totals.fetch(:failed_headline_gate_without_checks)
    assert_equal 0, totals.fetch(:shared_asset_with_terminal_extraction_without_checks)
  end

  test "accepts source and visual deterministic reviewer provenance" do
    source_reviewed = create_document("ca/nb/source-reviewed", 2025, "d" * 64)
    create_detailed_extraction(source_reviewed, "d" * 64)
    visual_reviewed = create_document("ca/nb/visual-reviewed", 2024, "e" * 64)
    create_detailed_extraction(
      visual_reviewed, "e" * 64,
      reviewer: Warehouse::FinancialStatementExtraction::Reviewer::VISUAL_REVIEWER
    )
    legacy_reviewed = create_document("ca/nb/legacy-reviewed", 2023, "f" * 64)
    create_detailed_extraction(legacy_reviewed, "f" * 64, reviewer: "legacy-local-reviewer")

    totals = Warehouse::FinancialStatementExtraction::CoverageAudit.new(
      release: @release, provinces: [ "nb" ]
    ).payload.fetch(:totals)

    assert_equal 1, totals.fetch(:approved_without_deterministic_reviewer)
  end

  private

  def create_document(canonical_id, year, sha)
    institution = Warehouse::Institution.create!(
      institution_release: @release, institution_source: @source, canonical_id:,
      name_en: canonical_id.split("/").last.titleize, institution_type: "government",
      government_level: "municipal", status: "active"
    )
    document = Warehouse::InstitutionDocument.create!(
      institution_release: @release, institution:, institution_source: @source,
      canonical_id: "#{canonical_id}/documents/financial-statements/#{year}/general",
      document_type: "financial-statements", document_variant: "general",
      fiscal_period_end: Date.new(year, 12, 31)
    )
    Warehouse::InstitutionDocumentAsset.create!(
      institution_release: @release, institution_document: document, content_sha256: sha,
      asset_role: "final", preferred: true, download_url: "https://example.test/#{sha}.pdf",
      retrieved_at: @release.published_at, archive_path: "sha256/#{sha.first(2)}/#{sha}.pdf",
      mime_type: "application/pdf", byte_size: 100, rights_status: "metadata_only"
    )
    document
  end

  def create_detailed_extraction(
    document, sha, reviewer: Warehouse::FinancialStatementExtraction::Reviewer::REVIEWER
  )
    extraction = Warehouse::FinancialStatementExtraction.create!(
      institution_release: @release, institution_canonical_id: document.institution.canonical_id,
      document_canonical_id: document.canonical_id, asset_sha256: sha,
      fiscal_year_end: document.fiscal_period_end,
      extractor_version: Warehouse::FinancialStatementExtraction::DetailedPipeline::EXTRACTOR_VERSION,
      status: "extracted", check_results: [ saved_check("pass") ]
    )
    extraction.financial_statement_facts.create!(
      concept: "total_revenue", value: 100, raw_text: "100", raw_label: "Total revenue",
      scale: 1, statement: "operations", source_page: 1, column_year: "2025",
      extraction_confidence: 1
    )
    extraction.financial_statement_line_items.create!(
      flow: "revenue", category: "Taxes", label: "Property tax", value: 100,
      raw_text: "100", scale: 1, source_page: 1, column_year: "2025", position: 0,
      extraction_confidence: 1
    )
    extraction.approve!(reviewer:)
    extraction
  end

  def create_failed_headline_extraction(document, sha)
    Warehouse::FinancialStatementExtraction.create!(
      institution_release: @release, institution_canonical_id: document.institution.canonical_id,
      document_canonical_id: document.canonical_id, asset_sha256: sha,
      fiscal_year_end: document.fiscal_period_end,
      extractor_version: Warehouse::FinancialStatementExtraction::Pipeline::EXTRACTOR_VERSION,
      status: "failed", error_message: "statement pages not found",
      check_results: [ saved_check("fail") ]
    )
  end

  def saved_check(status)
    { id: "source_identity", status:, detail: "saved result" }
  end
end
