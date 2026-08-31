#!/usr/bin/env ruby

require_relative "../config/environment"
require "optparse"

options = { release: "2026-08-27", provinces: [], limit: nil }
OptionParser.new do |parser|
  parser.banner = "Usage: script/revalidate_municipal_financial_headlines.rb [options]"
  parser.on("--release VERSION") { options[:release] = _1 }
  parser.on("--provinces x,y,z", Array) { options[:provinces] = _1.map(&:downcase) }
  parser.on("--limit COUNT", Integer) { options[:limit] = _1 }
end.parse!

release = Warehouse::InstitutionRelease.find_by!(version: options.fetch(:release))
candidates = Warehouse::FinancialStatementExtraction::CandidateSet.new(
  release:, provinces: options[:provinces].presence
)
abort "asset root is unavailable: #{candidates.asset_root}" unless candidates.asset_root.directory?
processed = 0
counts = Hash.new(0)

candidates.each do |candidate|
  break if options[:limit] && processed >= options[:limit]

  extraction = release.financial_statement_extractions.find_by(
    asset_sha256: candidate.asset_sha256,
    extractor_version: Warehouse::FinancialStatementExtraction::Pipeline::EXTRACTOR_VERSION,
    fiscal_year_end: candidate.fiscal_year_end,
    status: "needs_review"
  )
  next unless extraction
  next if extraction.llm_response_snapshot.blank?

  result = extraction.extractor.revalidate_headline(
    pdf_path: candidate.pdf_path,
    institution_name: candidate.institution_name,
    population: candidate.population
  )
  processed += 1
  counts[result.status] += 1
  puts({ id: extraction.id, document: extraction.document_canonical_id, status: result.status }.to_json)
rescue => error
  processed += 1
  counts["failed"] += 1
  puts({ id: extraction&.id, document: candidate.document_canonical_id,
    status: "failed", error: "#{error.class}: #{error.message}" }.compact.to_json)
end

puts({ release: release.version, processed:, summary: counts }.to_json)
