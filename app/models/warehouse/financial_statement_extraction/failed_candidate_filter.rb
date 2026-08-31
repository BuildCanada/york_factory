require "set"

class Warehouse::FinancialStatementExtraction::FailedCandidateFilter
  VARIANT_PRIORITY = {
    "consolidated" => 0,
    "general" => 1,
    "non-consolidated" => 2
  }.freeze

  attr_reader :release, :province, :candidates, :failed_keys, :included_keys,
    :approved_covered_keys, :review_pending_covered_keys, :duplicate_slot_keys, :unmatched_keys,
    :parser_versions, :failed_extractor_version

  def initialize(release:, province:, candidates:, parser_versions: nil,
    failed_extractor_version: Warehouse::FinancialStatementExtraction::DetailedPipeline::EXTRACTOR_VERSION)
    @release = release
    @province = province.to_s.downcase
    @candidates = candidates
    @parser_versions = Array(parser_versions).compact.map(&:to_s).uniq
    @failed_extractor_version = failed_extractor_version.to_s
    @candidates_by_key = candidates.group_by { key_for(_1) }
    @extractions_by_key = publication_scope.index_by { key_for(_1) }
    failed_scope = failure_scope.where(status: "failed")
    if self.parser_versions.any?
      failed_scope = failed_scope.where(
        "llm_response_snapshot ->> 'parser' IN (?)", self.parser_versions
      )
    end
    @failed_keys = failed_scope.pluck(:asset_sha256, :fiscal_year_end).to_set
    approved_slots = publication_scope.where(status: "approved")
      .pluck(:institution_canonical_id, :fiscal_year_end)
      .map { |institution, fiscal_year_end| [ institution, fiscal_year_end.year ] }.to_set
    review_pending_slots = publication_scope.where(status: %w[extracted needs_review])
      .pluck(:institution_canonical_id, :fiscal_year_end)
      .map { |institution, fiscal_year_end| [ institution, fiscal_year_end.year ] }.to_set
    @unmatched_keys = failed_keys - @candidates_by_key.keys.to_set
    @approved_covered_keys = (failed_keys - unmatched_keys).select do |key|
      @candidates_by_key.fetch(key).any? { approved_slots.include?(slot_for(_1)) }
    end.to_set
    @review_pending_covered_keys = (failed_keys - unmatched_keys - approved_covered_keys).select do |key|
      @candidates_by_key.fetch(key).any? { review_pending_slots.include?(slot_for(_1)) }
    end.to_set

    retryable_keys = failed_keys - unmatched_keys - approved_covered_keys - review_pending_covered_keys
    retryable_candidates = candidates.select { retryable_keys.include?(key_for(_1)) }
    @winner_by_slot = retryable_candidates.group_by { slot_for(_1) }
      .transform_values { select_winner(_1) }
    @eligible_document_ids = @winner_by_slot.values.map(&:document_id).to_set
    @included_keys = @winner_by_slot.values.map { key_for(_1) }.to_set
    @duplicate_slot_keys = retryable_keys - included_keys
  end

  def eligible?(candidate)
    @eligible_document_ids.include?(candidate.document_id)
  end

  def key_for(candidate_or_extraction)
    [ candidate_or_extraction.asset_sha256, candidate_or_extraction.fiscal_year_end ]
  end

  def report
    {
      province:,
      failed_extractor_version:,
      failed_parser_versions: parser_versions.presence,
      aggregated_failure_count: failed_keys.length,
      included_failure_count: included_keys.length,
      eligible_document_count: @eligible_document_ids.length,
      public_slot_count: @winner_by_slot.length,
      approved_elsewhere_excluded_count: approved_covered_keys.length,
      review_pending_elsewhere_excluded_count: review_pending_covered_keys.length,
      duplicate_slot_excluded_count: duplicate_slot_keys.length,
      unmatched_failure_count: unmatched_keys.length,
      reconciled: included_keys.length + approved_covered_keys.length +
        review_pending_covered_keys.length + duplicate_slot_keys.length + unmatched_keys.length ==
        failed_keys.length,
      approved_elsewhere_excluded: serialize_keys(approved_covered_keys),
      review_pending_elsewhere_excluded: serialize_keys(review_pending_covered_keys),
      duplicate_slot_excluded: serialize_duplicate_keys,
      unmatched_failures: serialize_keys(unmatched_keys)
    }
  end

  private

  def publication_scope
    release.financial_statement_extractions.where(
      extractor_version: Warehouse::FinancialStatementExtraction::DetailedPipeline::EXTRACTOR_VERSION
    ).where("institution_canonical_id LIKE ?", "ca/#{province}/%")
  end

  def failure_scope
    release.financial_statement_extractions.where(
      extractor_version: failed_extractor_version
    ).where("institution_canonical_id LIKE ?", "ca/#{province}/%")
  end

  def slot_for(candidate)
    [ candidate.institution_canonical_id, candidate.fiscal_year_end.year ]
  end

  def select_winner(slot_candidates)
    slot_candidates.min_by do |candidate|
      variant = candidate.document_canonical_id.split("/").last
      [ VARIANT_PRIORITY.fetch(variant, VARIANT_PRIORITY.length), candidate.document_id ]
    end
  end

  def serialize_keys(keys)
    keys.sort_by { |asset_sha256, fiscal_year_end| [ fiscal_year_end, asset_sha256 ] }.map do |key|
      asset_sha256, fiscal_year_end = key
      {
        asset_sha256:,
        fiscal_year_end: fiscal_year_end.iso8601,
        candidate_institutions: @candidates_by_key.fetch(key, []).map(&:institution_canonical_id).uniq.sort
      }
    end
  end

  def serialize_duplicate_keys
    serialize_keys(duplicate_slot_keys).map do |row|
      key = [ row.fetch(:asset_sha256), Date.iso8601(row.fetch(:fiscal_year_end)) ]
      superseded_slots = @candidates_by_key.fetch(key).filter_map do |candidate|
        winner = @winner_by_slot[slot_for(candidate)]
        next unless winner

        winner_key = key_for(winner)
        {
          institution_canonical_id: candidate.institution_canonical_id,
          fiscal_year: candidate.fiscal_year_end.year,
          winner_document_canonical_id: winner.document_canonical_id,
          winner_status: @extractions_by_key[winner_key]&.status
        }
      end
      row.merge(superseded_slots:)
    end
  end
end
