#!/usr/bin/env ruby

require_relative "../config/environment"
require "optparse"

options = {
  release: "2026-08-27", provinces: [ "sk" ],
  from_parser: "prairie-municipal-form-v1", limit: nil
}
OptionParser.new do |parser|
  parser.on("--release VERSION") { options[:release] = _1 }
  parser.on("--provinces LIST") { options[:provinces] = _1.split(",").map(&:strip) }
  parser.on("--from-parser VERSION") { options[:from_parser] = _1 }
  parser.on("--start-extraction-id ID", Integer) { options[:start_extraction_id] = _1 }
  parser.on("--limit COUNT", Integer) { options[:limit] = _1 }
  parser.on("--only-fallback-labels") { options[:only_fallback_labels] = true }
end.parse!

release = Warehouse::InstitutionRelease.find_by!(version: options.fetch(:release))
candidates = Warehouse::FinancialStatementExtraction::CandidateSet.new(
  release:, provinces: options.fetch(:provinces)
)
candidate_by_key = candidates.each.index_by { [ _1.asset_sha256, _1.fiscal_year_end ] }
scope = release.financial_statement_extractions.where(
  extractor_version: Warehouse::FinancialStatementExtraction::DetailedPipeline::EXTRACTOR_VERSION,
  status: "approved"
).where("llm_response_snapshot ->> 'parser' = ?", options.fetch(:from_parser)).order(:id)
province_clauses = options.fetch(:provinces).map { "institution_canonical_id LIKE ?" }.join(" OR ")
scope = scope.where(province_clauses, *options.fetch(:provinces).map { "ca/#{_1}/%" })
scope = scope.where("id > ?", options[:start_extraction_id]) if options[:start_extraction_id]
if options[:only_fallback_labels]
  risky_ids = Warehouse::FinancialStatementFact.where(
    raw_label: [ "FINANCIAL ASSETS", "LIABILITIES", "NON-FINANCIAL ASSETS" ]
  ).select(:financial_statement_extraction_id)
  scope = scope.where(id: risky_ids)
end
scope = scope.limit(options[:limit]) if options[:limit]
counts = Hash.new(0)

scope.find_each do |extraction|
  candidate = candidate_by_key.fetch([ extraction.asset_sha256, extraction.fiscal_year_end ])
  result = Warehouse::FinancialStatementExtraction::SaskatchewanFormPipeline.new(
    pdf_path: candidate.pdf_path,
    institution_canonical_id: candidate.institution_canonical_id,
    institution_name: candidate.institution_name,
    document_canonical_id: candidate.document_canonical_id,
    asset_sha256: candidate.asset_sha256,
    fiscal_year_end: candidate.fiscal_year_end,
    population: candidate.population
  ).run
  stored_facts = extraction.financial_statement_facts.to_h { [ _1.concept, _1.value ] }
  reparsed_facts = result.facts.to_h { [ _1.fetch(:concept), _1.fetch(:value) ] }
  line_item_signature = lambda do |item|
    attributes = item.respond_to?(:attributes) ? item.attributes.symbolize_keys : item
    attributes.slice(:flow, :category, :label, :value, :scale, :source_page, :column_year, :position)
      .merge(value: attributes.fetch(:value).to_d)
  end
  sort_line_items = ->(items) { items.sort_by { [ _1.fetch(:flow), _1.fetch(:position) ] } }
  stored_line_items = sort_line_items.call(
    extraction.financial_statement_line_items.map { line_item_signature.call(_1) }
  )
  reparsed_line_items = sort_line_items.call(result.line_items.map { line_item_signature.call(_1) })
  facts_match = stored_facts == reparsed_facts
  line_items_match = stored_line_items == reparsed_line_items
  status = facts_match && line_items_match ? "pass" : "mismatch"
  counts[status] += 1
  puts({
    extraction_id: extraction.id,
    document: extraction.document_canonical_id,
    from_parser: options.fetch(:from_parser),
    to_parser: Warehouse::FinancialStatementExtraction::SaskatchewanFormPipeline::PARSER_VERSION,
    status:,
    facts_match:,
    line_items_match:,
    stored_facts: stored_facts.transform_values(&:to_s),
    reparsed_facts: reparsed_facts.transform_values(&:to_s),
    stored_line_items: stored_line_items.map { _1.merge(value: _1.fetch(:value).to_s("F")) },
    reparsed_line_items: reparsed_line_items.map { _1.merge(value: _1.fetch(:value).to_s("F")) },
    verification_check_count: result.checks.length
  }.to_json)
rescue => error
  counts["failed"] += 1
  puts({
    extraction_id: extraction.id,
    document: extraction.document_canonical_id,
    from_parser: options.fetch(:from_parser),
    to_parser: Warehouse::FinancialStatementExtraction::SaskatchewanFormPipeline::PARSER_VERSION,
    status: "failed",
    error: "#{error.class}: #{error.message}"
  }.to_json)
end

puts({ release: release.version, summary: counts }.to_json)
