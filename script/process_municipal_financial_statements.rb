#!/usr/bin/env ruby

require_relative "../config/environment"
require "optparse"
require "set"

options = { release: "2026-08-27", rerun: "missing", limit: nil, start: nil, stop_before: nil }
OptionParser.new do |parser|
  parser.banner = "Usage: script/process_municipal_financial_statements.rb --province CODE [options]"
  parser.on("--release VERSION") { options[:release] = _1 }
  parser.on("--province CODE") { options[:province] = _1.downcase }
  parser.on("--years LIST") { options[:years] = _1.split(",").map { Integer(it) } }
  parser.on("--institutions LIST") { options[:institution_ids] = _1.split(",").map(&:strip) }
  parser.on("--rerun POLICY") { options[:rerun] = _1 }
  parser.on("--limit COUNT", Integer) { options[:limit] = _1 }
  parser.on("--start DOCUMENT_DATABASE_ID", Integer) { options[:start] = _1 }
  parser.on("--stop-before DOCUMENT_DATABASE_ID", Integer) { options[:stop_before] = _1 }
  parser.on("--document-ids LIST") { options[:document_ids] = _1.split(",").map { Integer(it) } }
  parser.on("--exclude-document-ids LIST") do |value|
    options[:excluded_document_ids] = value.split(",").map { Integer(it) }
  end
  parser.on("--failed-only") { options[:failed_only] = true }
  parser.on("--failed-extractor TARGET", %w[headline detailed]) do |value|
    options[:failed_extractor] = value
  end
  parser.on("--failed-parser LIST") do |value|
    options[:failed_parser_versions] ||= []
    options[:failed_parser_versions].concat(value.split(",").map(&:strip).reject(&:empty?))
  end
end.parse!
abort "missing option: province" unless options[:province]
abort "--failed-only requires --rerun failed" if options[:failed_only] && options[:rerun] != "failed"
abort "--failed-extractor requires --failed-only" if options[:failed_extractor] && !options[:failed_only]
if options[:failed_parser_versions]&.any? && !options[:failed_only]
  abort "--failed-parser requires --failed-only"
end
if options[:failed_extractor] == "headline" && options[:failed_parser_versions]&.any?
  abort "--failed-parser only supports the detailed failed extractor"
end

release = Warehouse::InstitutionRelease.find_by!(version: options.fetch(:release))
candidates = Warehouse::FinancialStatementExtraction::CandidateSet.new(
  release:, provinces: [ options.fetch(:province) ], years: options[:years],
  institution_ids: options[:institution_ids]
)
abort "asset root is unavailable: #{candidates.asset_root}" unless candidates.asset_root.directory?

processor = Warehouse::FinancialStatementExtraction::Processor.new(release:, rerun: options.fetch(:rerun))
candidate_window = Warehouse::FinancialStatementExtraction::CandidateWindow.new(
  start: options[:start], stop_before: options[:stop_before],
  document_ids: options[:document_ids], excluded_document_ids: options[:excluded_document_ids]
)
candidate_rows = options[:failed_only] ? candidates.each.to_a : candidates.each(start: options[:start])
failed_filter = if options[:failed_only]
  failed_extractor_version = if options[:failed_extractor] == "headline"
    Warehouse::FinancialStatementExtraction::Pipeline::EXTRACTOR_VERSION
  else
    Warehouse::FinancialStatementExtraction::DetailedPipeline::EXTRACTOR_VERSION
  end
  Warehouse::FinancialStatementExtraction::FailedCandidateFilter.new(
    release:, province: options.fetch(:province), candidates: candidate_rows,
    parser_versions: options[:failed_parser_versions], failed_extractor_version:
  )
end
if failed_filter
  puts({ failed_only_scope: failed_filter.report }.to_json)
  abort "failed-only scope has unmatched persisted failures" if failed_filter.unmatched_keys.any?
end
counts = Hash.new(0)
processed = 0
consecutive_source_failures = 0
processed_failed_keys = Set.new

candidate_rows.each do |candidate|
  next if candidate_window.before_start?(candidate)
  break if candidate_window.at_or_after_stop?(candidate)
  next unless candidate_window.selected?(candidate)
  next if candidate_window.excluded?(candidate)
  break if options[:limit] && processed >= options[:limit]
  if failed_filter
    next unless failed_filter.eligible?(candidate)
    next unless processed_failed_keys.add?(failed_filter.key_for(candidate))
  end

  result = processor.call(candidate)
  processed += 1
  counts[result.status] += 1
  consecutive_source_failures = if result.status.in?(%w[missing_asset concurrent_skip])
    consecutive_source_failures + 1
  else
    0
  end
  puts({
    index: processed, document_id: candidate.document_id,
    document: candidate.document_canonical_id, fiscal_year: candidate.fiscal_year_end.year,
    status: result.status, stage: result.stage, extraction_id: result.extraction_id,
    error: result.error
  }.compact.to_json)
  abort "source access circuit opened after three consecutive failures" if consecutive_source_failures >= 3
end

puts({ summary: counts, processed:, failed_only: options[:failed_only] || false }.to_json)
