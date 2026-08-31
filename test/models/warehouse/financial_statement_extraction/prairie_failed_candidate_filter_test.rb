require "test_helper"

class Warehouse::FinancialStatementExtraction::PrairieFailedCandidateFilterTest < ActiveSupport::TestCase
  setup do
    @release = Warehouse::InstitutionRelease.create!(
      version: "2026-08-30", effective_on: Date.new(2026, 8, 30), schema_version: "1.0",
      published_at: Time.utc(2026, 8, 30), geography_vintage: 2021, attribution: "Test"
    )
    @source = Warehouse::InstitutionSource.create!(
      institution_release: @release, canonical_id: "ca/sources/prairie-filter-test",
      publisher_name: "Test", title_en: "Test", url: "https://example.test/source",
      retrieved_at: @release.published_at, languages: [ "en" ]
    )
  end

  test "includes only failed municipality-years without an approved variant" do
    excluded_failed = create_document("ca/ab/approved-elsewhere", 2025, "a" * 64, "general")
    approved_variant = create_document("ca/ab/approved-elsewhere", 2025, "b" * 64, "audited")
    failed_only = create_document("ca/ab/failed-only", 2024, "c" * 64, "general")
    rejected_failed = create_document("ca/ab/rejected-only", 2023, "d" * 64, "general")
    rejected_variant = create_document("ca/ab/rejected-only", 2023, "e" * 64, "audited")

    create_extraction(excluded_failed, "a" * 64, "failed")
    create_extraction(approved_variant, "b" * 64, "approved")
    create_extraction(failed_only, "c" * 64, "failed")
    create_extraction(rejected_failed, "d" * 64, "failed")
    create_extraction(rejected_variant, "e" * 64, "rejected")

    candidates = Warehouse::FinancialStatementExtraction::CandidateSet.new(
      release: @release, provinces: [ "ab" ]
    ).each.to_a
    by_document = candidates.index_by(&:document_canonical_id)
    filter = Warehouse::FinancialStatementExtraction::FailedCandidateFilter.new(
      release: @release, province: "ab", candidates:
    )

    refute filter.eligible?(by_document.fetch(excluded_failed.canonical_id))
    refute filter.eligible?(by_document.fetch(approved_variant.canonical_id))
    assert filter.eligible?(by_document.fetch(failed_only.canonical_id))
    assert filter.eligible?(by_document.fetch(rejected_failed.canonical_id))
    refute filter.eligible?(by_document.fetch(rejected_variant.canonical_id))

    report = filter.report
    assert_equal 3, report.fetch(:aggregated_failure_count)
    assert_equal 2, report.fetch(:included_failure_count)
    assert_equal 2, report.fetch(:eligible_document_count)
    assert_equal 2, report.fetch(:public_slot_count)
    assert_equal 1, report.fetch(:approved_elsewhere_excluded_count)
    assert_equal 0, report.fetch(:review_pending_elsewhere_excluded_count)
    assert_equal 0, report.fetch(:duplicate_slot_excluded_count)
    assert_equal 0, report.fetch(:unmatched_failure_count)
    assert report.fetch(:reconciled)
    assert_equal [ "ca/ab/approved-elsewhere" ],
      report.dig(:approved_elsewhere_excluded, 0, :candidate_institutions)
  end

  test "uses public years for approved coverage and selects one ranked variant" do
    covered_failure = create_document(
      "ca/ab/year-covered", 2025, "1" * 64, "general",
      fiscal_period_end: Date.new(2025, 12, 31)
    )
    approved_different_date = create_document(
      "ca/ab/year-covered", 2025, "2" * 64, "consolidated",
      fiscal_period_end: Date.new(2025, 3, 31)
    )
    consolidated = create_document("ca/ab/ranked", 2024, "3" * 64, "consolidated")
    general = create_document("ca/ab/ranked", 2024, "4" * 64, "general")
    create_extraction(covered_failure, "1" * 64, "failed")
    create_extraction(approved_different_date, "2" * 64, "approved")
    create_extraction(consolidated, "3" * 64, "failed")
    create_extraction(general, "4" * 64, "failed")

    candidates = Warehouse::FinancialStatementExtraction::CandidateSet.new(
      release: @release, provinces: [ "ab" ]
    ).each.to_a
    by_document = candidates.index_by(&:document_canonical_id)
    filter = Warehouse::FinancialStatementExtraction::FailedCandidateFilter.new(
      release: @release, province: "ab", candidates:
    )

    refute filter.eligible?(by_document.fetch(covered_failure.canonical_id))
    assert filter.eligible?(by_document.fetch(consolidated.canonical_id))
    refute filter.eligible?(by_document.fetch(general.canonical_id))
    report = filter.report
    assert_equal 3, report.fetch(:aggregated_failure_count)
    assert_equal 1, report.fetch(:included_failure_count)
    assert_equal 1, report.fetch(:approved_elsewhere_excluded_count)
    assert_equal 0, report.fetch(:review_pending_elsewhere_excluded_count)
    assert_equal 1, report.fetch(:duplicate_slot_excluded_count)
    assert_equal 1, report.fetch(:eligible_document_count)
    assert_equal 1, report.fetch(:public_slot_count)
    assert report.fetch(:reconciled)
    superseded = report.fetch(:duplicate_slot_excluded).sole.fetch(:superseded_slots).sole
    assert_equal consolidated.canonical_id, superseded.fetch(:winner_document_canonical_id)
    assert_equal "failed", superseded.fetch(:winner_status)
  end

  test "counts a shared failed identity once while exposing each public slot winner" do
    first = create_document("ca/ab/shared-first", 2024, "5" * 64, "consolidated")
    second = create_document("ca/ab/shared-second", 2024, "5" * 64, "consolidated")
    create_extraction(first, "5" * 64, "failed")
    candidates = Warehouse::FinancialStatementExtraction::CandidateSet.new(
      release: @release, provinces: [ "ab" ]
    ).each.to_a
    filter = Warehouse::FinancialStatementExtraction::FailedCandidateFilter.new(
      release: @release, province: "ab", candidates:
    )

    assert candidates.all? { filter.eligible?(_1) }
    assert_equal 1, filter.report.fetch(:included_failure_count)
    assert_equal 2, filter.report.fetch(:eligible_document_count)
    assert_equal 2, filter.report.fetch(:public_slot_count)
    assert filter.report.fetch(:reconciled)
  end

  test "excludes a failed variant while its public year is awaiting review" do
    failed = create_document("ca/ab/review-pending", 2024, "7" * 64, "general")
    awaiting_review = create_document(
      "ca/ab/review-pending", 2024, "8" * 64, "consolidated",
      fiscal_period_end: Date.new(2024, 3, 31)
    )
    create_extraction(failed, "7" * 64, "failed")
    create_extraction(awaiting_review, "8" * 64, "needs_review")
    candidates = Warehouse::FinancialStatementExtraction::CandidateSet.new(
      release: @release, provinces: [ "ab" ]
    ).each.to_a
    filter = Warehouse::FinancialStatementExtraction::FailedCandidateFilter.new(
      release: @release, province: "ab", candidates:
    )

    refute filter.eligible?(candidates.find { _1.document_canonical_id == failed.canonical_id })
    assert_equal 0, filter.report.fetch(:included_failure_count)
    assert_equal 1, filter.report.fetch(:review_pending_elsewhere_excluded_count)
    assert filter.report.fetch(:reconciled)
  end

  test "reports persisted failures absent from the candidate set" do
    document = create_document("ca/ab/unmatched", 2024, "6" * 64, "consolidated")
    create_extraction(document, "6" * 64, "failed")
    filter = Warehouse::FinancialStatementExtraction::FailedCandidateFilter.new(
      release: @release, province: "ab", candidates: []
    )

    assert_equal 1, filter.unmatched_keys.length
    assert_equal 1, filter.report.fetch(:unmatched_failure_count)
    assert filter.report.fetch(:reconciled)
  end

  test "targets failed parser versions while keeping slot coverage parser agnostic" do
    target = create_document("ca/ab/parser-target", 2024, "9" * 64, "general")
    pending_sibling = create_document("ca/ab/parser-target", 2024, "a" * 64, "consolidated")
    other_failure = create_document("ca/ab/other-parser", 2023, "b" * 64, "consolidated")
    create_extraction(target, "9" * 64, "failed", parser: "target-v1")
    create_extraction(pending_sibling, "a" * 64, "needs_review", parser: "other-v1")
    create_extraction(other_failure, "b" * 64, "failed", parser: "other-v1")
    candidates = Warehouse::FinancialStatementExtraction::CandidateSet.new(
      release: @release, provinces: [ "ab" ]
    ).each.to_a
    filter = Warehouse::FinancialStatementExtraction::FailedCandidateFilter.new(
      release: @release, province: "ab", candidates:, parser_versions: [ "target-v1" ]
    )

    assert_equal [ "target-v1" ], filter.report.fetch(:failed_parser_versions)
    assert_equal 1, filter.report.fetch(:aggregated_failure_count)
    assert_equal 0, filter.report.fetch(:included_failure_count)
    assert_equal 1, filter.report.fetch(:review_pending_elsewhere_excluded_count)
    assert filter.report.fetch(:reconciled)
  end

  test "targets headline failures while keeping publication coverage pinned to detailed rows" do
    headline_target = create_document("ca/ab/headline-target", 2024, "c" * 64, "general")
    detailed_failure = create_document("ca/ab/detailed-target", 2023, "d" * 64, "general")
    covered_headline = create_document("ca/ab/headline-covered", 2022, "e" * 64, "general")
    covered_detailed = create_document("ca/ab/headline-covered", 2022, "f" * 64, "consolidated")
    create_extraction(headline_target, "c" * 64, "failed", extractor: :headline)
    create_extraction(detailed_failure, "d" * 64, "failed")
    create_extraction(covered_headline, "e" * 64, "failed", extractor: :headline)
    create_extraction(covered_detailed, "f" * 64, "approved")
    candidates = Warehouse::FinancialStatementExtraction::CandidateSet.new(
      release: @release, provinces: [ "ab" ]
    ).each.to_a
    by_document = candidates.index_by(&:document_canonical_id)

    detailed_filter = Warehouse::FinancialStatementExtraction::FailedCandidateFilter.new(
      release: @release, province: "ab", candidates:
    )
    headline_filter = Warehouse::FinancialStatementExtraction::FailedCandidateFilter.new(
      release: @release, province: "ab", candidates:,
      failed_extractor_version: Warehouse::FinancialStatementExtraction::Pipeline::EXTRACTOR_VERSION
    )

    assert detailed_filter.eligible?(by_document.fetch(detailed_failure.canonical_id))
    refute detailed_filter.eligible?(by_document.fetch(headline_target.canonical_id))
    assert headline_filter.eligible?(by_document.fetch(headline_target.canonical_id))
    refute headline_filter.eligible?(by_document.fetch(detailed_failure.canonical_id))
    refute headline_filter.eligible?(by_document.fetch(covered_headline.canonical_id))
    assert_equal Warehouse::FinancialStatementExtraction::Pipeline::EXTRACTOR_VERSION,
      headline_filter.report.fetch(:failed_extractor_version)
    assert_equal 1, headline_filter.report.fetch(:included_failure_count)
    assert_equal 1, headline_filter.report.fetch(:approved_elsewhere_excluded_count)
    assert headline_filter.report.fetch(:reconciled)
  end

  private

  def create_document(canonical_id, year, sha, variant, fiscal_period_end: Date.new(year, 12, 31))
    institution = @release.institutions.find_or_create_by!(canonical_id:) do |row|
      row.assign_attributes(
        institution_source: @source, name_en: canonical_id.split("/").last.titleize,
        institution_type: "government", government_level: "municipal", status: "active"
      )
    end
    document = Warehouse::InstitutionDocument.create!(
      institution_release: @release, institution:, institution_source: @source,
      canonical_id: "#{canonical_id}/documents/financial-statements/#{year}/#{variant}",
      document_type: "financial-statements", document_variant: variant,
      fiscal_period_end:
    )
    Warehouse::InstitutionDocumentAsset.create!(
      institution_release: @release, institution_document: document, content_sha256: sha,
      asset_role: "final", preferred: true, download_url: "https://example.test/#{sha}.pdf",
      retrieved_at: @release.published_at, archive_path: "sha256/#{sha.first(2)}/#{sha}.pdf",
      mime_type: "application/pdf", byte_size: 100, rights_status: "metadata_only"
    )
    document
  end

  def create_extraction(document, sha, status, parser: nil, extractor: :detailed)
    extraction = Warehouse::FinancialStatementExtraction.create!(
      institution_release: @release, institution_canonical_id: document.institution.canonical_id,
      document_canonical_id: document.canonical_id, asset_sha256: sha,
      fiscal_year_end: document.fiscal_period_end,
      extractor_version: extractor == :headline ?
        Warehouse::FinancialStatementExtraction::Pipeline::EXTRACTOR_VERSION :
        Warehouse::FinancialStatementExtraction::DetailedPipeline::EXTRACTOR_VERSION,
      status: status.in?(%w[approved rejected]) ? "extracted" : status,
      llm_response_snapshot: parser ? { "parser" => parser } : nil,
      check_results: [ { id: "deterministic_parser", status: status == "approved" ? "pass" : "fail",
        detail: "saved" } ]
    )
    reviewer = Warehouse::FinancialStatementExtraction::Reviewer::REVIEWER
    extraction.approve!(reviewer:) if status == "approved"
    extraction.reject!(reviewer:) if status == "rejected"
    extraction
  end
end
