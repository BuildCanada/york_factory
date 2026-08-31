#!/usr/bin/env ruby

require_relative "../config/environment"
require "optparse"

options = { release: "2026-08-27", limit: nil }
OptionParser.new do |parser|
  parser.on("--release VERSION") { options[:release] = _1 }
  parser.on("--limit COUNT", Integer) { options[:limit] = _1 }
end.parse!

release = Warehouse::InstitutionRelease.find_by!(version: options.fetch(:release))
scope = release.financial_statement_extractions.where(
  extractor_version: Warehouse::FinancialStatementExtraction::DetailedPipeline::EXTRACTOR_VERSION,
  status: %w[extracted needs_review approved rejected]
).order(:id)
scope = scope.limit(options[:limit]) if options[:limit]
counts = Hash.new(0)

scope.find_each do |extraction|
  mismatches = []
  extraction.financial_statement_facts.find_each do |fact|
    expected = Warehouse::FinancialStatementExtraction::NumberParser.parse(
      fact.raw_text, raw_label: fact.raw_label, concept: fact.concept
    ) * fact.scale
    next if expected == fact.value

    mismatches << { type: "fact", id: fact.id, raw_text: fact.raw_text,
      stored: fact.value.to_s, expected: expected.to_s }
  end
  extraction.financial_statement_line_items.find_each do |item|
    expected = Warehouse::FinancialStatementExtraction::NumberParser.parse(item.raw_text) * item.scale
    next if expected == item.value

    mismatches << { type: "line_item", id: item.id, raw_text: item.raw_text,
      stored: item.value.to_s, expected: expected.to_s }
  end
  result = mismatches.empty? ? "pass" : "mismatch"
  counts[result] += 1
  puts({ id: extraction.id, institution: extraction.institution_canonical_id,
    fiscal_year: extraction.fiscal_year_end.year, status: extraction.status,
    result:, mismatches: }.to_json)
rescue => error
  counts["error"] += 1
  puts({ id: extraction.id, institution: extraction.institution_canonical_id,
    fiscal_year: extraction.fiscal_year_end.year, status: extraction.status,
    result: "error", error: "#{error.class}: #{error.message}" }.to_json)
end

puts({ summary: counts }.to_json)
