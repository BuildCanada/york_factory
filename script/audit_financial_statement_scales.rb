#!/usr/bin/env ruby

require_relative "../config/environment"
require "optparse"

options = { release: "2026-08-27", limit: nil, asset_root: Warehouse::FinancialStatementExtraction::CandidateSet::DEFAULT_ASSET_ROOT }
OptionParser.new do |parser|
  parser.on("--release VERSION") { options[:release] = _1 }
  parser.on("--limit COUNT", Integer) { options[:limit] = _1 }
  parser.on("--shard INDEX/COUNT") do |value|
    options[:shard_index], options[:shard_count] = value.split("/", 2).map { |part| Integer(part) }
  end
  parser.on("--asset-root PATH") { options[:asset_root] = Pathname(_1).expand_path }
end.parse!

release = Warehouse::InstitutionRelease.find_by!(version: options[:release])
scope = release.financial_statement_extractions.where(
  extractor_version: Warehouse::FinancialStatementExtraction::DetailedPipeline::EXTRACTOR_VERSION,
  status: %w[extracted approved]
).where("jsonb_exists(llm_response_snapshot, 'parser')").order(:id)
scope = scope.where("MOD(id, ?) = ?", options[:shard_count], options[:shard_index]) if options[:shard_count]
scope = scope.limit(options[:limit]) if options[:limit]
asset_root = Pathname(options[:asset_root]).expand_path
counts = Hash.new(0)

scope.find_each do |extraction|
  document = release.institution_documents.find_by!(canonical_id: extraction.document_canonical_id)
  asset = document.institution_document_assets.find_by!(content_sha256: extraction.asset_sha256)
  pdf_path = asset_root.join(asset.archive_path).expand_path
  raise "asset path escapes root" unless pdf_path.to_s.start_with?("#{asset_root}/")
  raise "missing archived PDF" unless pdf_path.file?

  pages = (extraction.financial_statement_facts.pluck(:source_page) +
    extraction.financial_statement_line_items.pluck(:source_page)).uniq.sort
  texts = pages.map do |page|
    stdout, stderr, status = Open3.capture3(
      "pdftotext", "-f", page.to_s, "-l", page.to_s, "-layout", "-enc", "UTF-8", pdf_path.to_s, "-"
    )
    raise "pdftotext page #{page} failed: #{stderr}" unless status.success?
    stdout.force_encoding(Encoding::UTF_8).scrub
  end
  source_scale = Warehouse::FinancialStatementExtraction::ScaleDetector.detect(texts)
  stored_scales = (extraction.financial_statement_facts.pluck(:scale) +
    extraction.financial_statement_line_items.pluck(:scale)).uniq.sort
  result = stored_scales == [ source_scale ] ? "pass" : "mismatch"
  counts[result] += 1
  puts({ id: extraction.id, institution: extraction.institution_canonical_id,
    fiscal_year: extraction.fiscal_year_end.year, status: extraction.status,
    result:, source_scale:, stored_scales: }.to_json)
rescue => error
  counts["error"] += 1
  puts({ id: extraction.id, institution: extraction.institution_canonical_id,
    fiscal_year: extraction.fiscal_year_end.year, result: "error",
    error: "#{error.class}: #{error.message}" }.to_json)
end

puts({ summary: counts }.to_json)
