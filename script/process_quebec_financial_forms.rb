#!/usr/bin/env ruby

require_relative "../config/environment"
require "optparse"

options = { release: "2026-08-27", limit: nil, start: nil, stop_before: nil }
OptionParser.new do |parser|
  parser.banner = "Usage: script/process_quebec_financial_forms.rb [options]"
  parser.on("--release VERSION") { options[:release] = _1 }
  parser.on("--limit COUNT", Integer) { options[:limit] = _1 }
  parser.on("--start DOCUMENT_DATABASE_ID", Integer) { options[:start] = _1 }
  parser.on("--stop-before DOCUMENT_DATABASE_ID", Integer) { options[:stop_before] = _1 }
end.parse!

release = Warehouse::InstitutionRelease.find_by!(version: options.fetch(:release))
candidates = Warehouse::FinancialStatementExtraction::CandidateSet.new(release:, provinces: [ "qc" ])
abort "asset root is unavailable: #{candidates.asset_root}" unless candidates.asset_root.directory?
processor = Warehouse::FinancialStatementExtraction::QuebecFormProcessor.new(release:)
counts = Hash.new(0)
processed = 0
consecutive_missing_assets = 0

candidates.each(start: options[:start]) do |candidate|
  break if options[:stop_before] && candidate.document_id >= options[:stop_before]
  break if options[:limit] && processed >= options[:limit]

  result = processor.call(candidate)
  processed += 1
  counts[result.status] += 1
  consecutive_missing_assets = result.status == "missing_asset" ? consecutive_missing_assets + 1 : 0
  puts({ index: processed, status: result.status, document: result.document_canonical_id,
    extraction_id: result.detailed_extraction_id, error: result.error }.compact.to_json)
  abort "asset root appears unavailable after three consecutive missing PDFs" if consecutive_missing_assets >= 3
end

puts({ summary: counts, processed: }.to_json)
