#!/usr/bin/env ruby

require_relative "../config/environment"
require "optparse"
require "set"

options = { release: "2026-08-27", province: "sk", limit: nil, start: nil, stop_before: nil }
OptionParser.new do |parser|
  parser.banner = "Usage: script/process_saskatchewan_financial_forms.rb [options]"
  parser.on("--release VERSION") { options[:release] = _1 }
  parser.on("--province CODE") { options[:province] = _1.downcase }
  parser.on("--limit COUNT", Integer) { options[:limit] = _1 }
  parser.on("--start DOCUMENT_DATABASE_ID", Integer) { options[:start] = _1 }
  parser.on("--stop-before DOCUMENT_DATABASE_ID", Integer) { options[:stop_before] = _1 }
  parser.on("--failed-only") { options[:failed_only] = true }
end.parse!

release = Warehouse::InstitutionRelease.find_by!(version: options.fetch(:release))
candidates = Warehouse::FinancialStatementExtraction::CandidateSet.new(release:, provinces: [ options[:province] ])
abort "asset root is unavailable: #{candidates.asset_root}" unless candidates.asset_root.directory?
processor = Warehouse::FinancialStatementExtraction::SaskatchewanFormProcessor.new(release:)
candidate_window = Warehouse::FinancialStatementExtraction::CandidateWindow.new(
  start: options[:start], stop_before: options[:stop_before]
)
candidate_rows = candidates.each.to_a
failed_filter = if options[:failed_only]
  Warehouse::FinancialStatementExtraction::FailedCandidateFilter.new(
    release:, province: options.fetch(:province), candidates: candidate_rows
  )
end
if failed_filter
  puts({ failed_only_scope: failed_filter.report }.to_json)
  abort "failed-only scope has unmatched persisted failures" if failed_filter.unmatched_keys.any?
end
counts = Hash.new(0)
processed = 0
consecutive_missing_assets = 0
processed_failed_keys = Set.new

candidate_rows.each do |candidate|
  next if candidate_window.before_start?(candidate)
  break if candidate_window.at_or_after_stop?(candidate)
  break if options[:limit] && processed >= options[:limit]
  if failed_filter
    next unless failed_filter.eligible?(candidate)
    next unless processed_failed_keys.add?(failed_filter.key_for(candidate))
  end

  result = processor.call(candidate)
  processed += 1
  counts[result.status] += 1
  consecutive_missing_assets = result.status == "missing_asset" ? consecutive_missing_assets + 1 : 0
  puts({ index: processed, status: result.status, document: result.document_canonical_id,
    extraction_id: result.detailed_extraction_id, error: result.error }.compact.to_json)
  abort "asset root appears unavailable after three consecutive missing PDFs" if consecutive_missing_assets >= 3
end

puts({ summary: counts, processed:, failed_only: options[:failed_only] || false }.to_json)
