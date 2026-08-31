class Warehouse::FinancialStatementExtraction::CoverageAudit
  TERMINAL_STATUSES = %w[extracted needs_review approved rejected failed].freeze

  attr_reader :release, :provinces

  def initialize(release:, provinces: nil)
    @release = release
    @provinces = provinces
  end

  def payload
    candidate_rows = candidates.each.to_a
    candidate_groups = candidate_rows.group_by { identity_key(_1) }
    predicted_owner_by_key = candidate_groups.transform_values { _1.min_by(&:document_id) }
    detailed_by_key = extraction_scope(
      Warehouse::FinancialStatementExtraction::DetailedPipeline::EXTRACTOR_VERSION
    ).includes(:financial_statement_facts, :financial_statement_line_items).index_by do |extraction|
      identity_key(extraction)
    end
    headline_by_key = extraction_scope(
      Warehouse::FinancialStatementExtraction::Pipeline::EXTRACTOR_VERSION
    ).index_by { identity_key(_1) }
    records = candidate_rows.map do |candidate|
      record_for(
        candidate:, candidate_groups:, predicted_owner_by_key:, detailed_by_key:, headline_by_key:
      )
    end

    {
      generated_at: Time.current.iso8601,
      release: release.version,
      extractor_version: Warehouse::FinancialStatementExtraction::DetailedPipeline::EXTRACTOR_VERSION,
      definitions: {
        preferred_asset: "one preferred archived PDF candidate, including document variants",
        institution_year: "one reporting institution and fiscal year, matching the API publication surface",
        approved: "publishable only after saved verification checks and reviewer provenance",
        shared_asset: "a non-owner candidate sharing extraction identity with another preferred PDF; " \
          "the persisted row wins, otherwise the lowest document id predicts ownership"
      },
      totals: summarize(records),
      provinces: records.group_by { _1.fetch(:province) }.sort.to_h do |province, rows|
        [ province, summarize(rows) ]
      end,
      records:
    }
  end

  private

  def candidates
    Warehouse::FinancialStatementExtraction::CandidateSet.new(release:, provinces:)
  end

  def extraction_scope(extractor_version)
    release.financial_statement_extractions.where(extractor_version:)
  end

  def identity_key(candidate_or_extraction)
    [ candidate_or_extraction.asset_sha256, candidate_or_extraction.fiscal_year_end ]
  end

  def record_for(candidate:, candidate_groups:, predicted_owner_by_key:, detailed_by_key:, headline_by_key:)
    key = identity_key(candidate)
    detailed = detailed_by_key[key]
    headline = headline_by_key[key]
    extraction = detailed || headline
    predicted_owner = predicted_owner_by_key.fetch(key)
    owner_document = extraction&.document_canonical_id || predicted_owner.document_canonical_id
    shared_asset = candidate.document_canonical_id != owner_document
    shared_owner = candidate_groups.fetch(key).find do |group_candidate|
      group_candidate.document_canonical_id == owner_document
    end || predicted_owner
    status = record_status(shared_asset:, detailed:, headline:)
    checks = Warehouse::FinancialStatementExtraction.verification_checks(extraction&.check_results)
    check_statuses = checks.map { _1.fetch(:status) }.tally
    shared_with_institution = if shared_asset
      extraction&.institution_canonical_id || shared_owner.institution_canonical_id
    end

    {
      province: candidate.institution_canonical_id.split("/").fetch(1),
      institution_canonical_id: candidate.institution_canonical_id,
      document_canonical_id: candidate.document_canonical_id,
      asset_sha256: candidate.asset_sha256,
      fiscal_year: candidate.fiscal_year_end.year,
      extraction_id: extraction&.id,
      extraction_stage: extraction_stage(shared_asset:, detailed:, headline:),
      status:,
      shared_extraction_status: shared_asset ? extraction&.status : nil,
      shared_with_document_canonical_id: shared_asset ? owner_document : nil,
      shared_with_institution_canonical_id: shared_with_institution,
      parser: extraction&.llm_response_snapshot&.fetch("parser", nil),
      error: extraction&.error_message,
      reviewed_by: extraction&.reviewed_by,
      reviewed_at: extraction&.reviewed_at&.iso8601,
      verification: {
        total: checks.length,
        pass: check_statuses.fetch("pass", 0),
        skip: check_statuses.fetch("skip", 0),
        fail: checks.length - check_statuses.fetch("pass", 0) - check_statuses.fetch("skip", 0),
        checks:
      },
      fact_count: shared_asset ? 0 : (detailed&.financial_statement_facts&.length || 0),
      line_item_count: shared_asset ? 0 : (detailed&.financial_statement_line_items&.length || 0)
    }
  end

  def record_status(shared_asset:, detailed:, headline:)
    return "shared_asset" if shared_asset
    return detailed.status if detailed
    return "failed_headline_gate" if headline&.status == "failed"
    return "headline_#{headline.status}" if headline

    "unattempted"
  end

  def extraction_stage(shared_asset:, detailed:, headline:)
    return "shared_asset" if shared_asset
    return "detailed" if detailed

    "headline_gate" if headline
  end

  def summarize(rows)
    institution_years = rows.group_by do |row|
      [ row.fetch(:institution_canonical_id), row.fetch(:fiscal_year) ]
    end
    status_counts = rows.map { _1.fetch(:status) }.tally
    published_institution_year_count = institution_years.count do |_, variants|
      variants.any? { _1.fetch(:status) == "approved" }
    end
    approved_asset_count = status_counts.fetch("approved", 0)
    unattempted_asset_count = status_counts.fetch("unattempted", 0)

    {
      preferred_asset_count: rows.length,
      institution_year_count: institution_years.length,
      published_institution_year_count:,
      status_counts:,
      parser_counts: rows.filter_map { _1.fetch(:parser) }.tally,
      reconciliation: {
        classified_asset_count: rows.length - unattempted_asset_count,
        unclassified_asset_count: unattempted_asset_count,
        approved_asset_count:,
        approved_duplicate_variant_count: approved_asset_count - published_institution_year_count,
        awaiting_review_asset_count: status_counts.fetch("extracted", 0) +
          status_counts.fetch("needs_review", 0),
        rejected_asset_count: status_counts.fetch("rejected", 0)
      },
      approved_without_checks: without_checks(rows, "approved"),
      failed_headline_gate_without_checks: without_checks(rows, "failed_headline_gate"),
      shared_asset_with_terminal_extraction_without_checks: rows.count do |row|
        row.fetch(:status) == "shared_asset" &&
          row.fetch(:shared_extraction_status).in?(TERMINAL_STATUSES) &&
          row.dig(:verification, :total).zero?
      end,
      approved_without_deterministic_reviewer: rows.count do |row|
        row.fetch(:status) == "approved" && !row.fetch(:reviewed_by).in?(
          Warehouse::FinancialStatementExtraction::Reviewer::DETERMINISTIC_REVIEWERS
        )
      end
    }
  end

  def without_checks(rows, status)
    rows.count do |row|
      row.fetch(:status) == status && row.dig(:verification, :total).zero?
    end
  end
end
