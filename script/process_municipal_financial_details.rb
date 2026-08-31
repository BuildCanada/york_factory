#!/usr/bin/env ruby

require_relative "../config/environment"
require "optparse"

options = {}
OptionParser.new do |parser|
  parser.banner = "Usage: bin/rails runner script/process_municipal_financial_details.rb --release VERSION --config PATH [--cities city,city] [--years 2024,2025]"
  parser.on("--release VERSION") { |value| options[:release] = value }
  parser.on("--config PATH") { |value| options[:config] = Pathname(value).expand_path }
  parser.on("--cities LIST") { |value| options[:cities] = value.split(",").map(&:strip) }
  parser.on("--years LIST") { |value| options[:years] = value.split(",").map { Integer(_1) } }
end.parse!
missing = %i[release config].reject { |key| options[key].present? }
abort "missing options: #{missing.join(', ')}" if missing.any?

release = Warehouse::InstitutionRelease.find_by!(version: options.fetch(:release))
entries = JSON.parse(options.fetch(:config).read).fetch("entries")
entries.select! { |entry| entry.fetch("city").in?(options.fetch(:cities)) } if options[:cities]
entries.select! do |entry|
  year = Date.iso8601(entry["fiscal_year_end"] || JSON.parse(Pathname(entry.fetch("extraction_path")).read).fetch("fiscal_year_end")).year
  year.in?(options.fetch(:years))
end if options[:years]
results = []

entries.each do |entry|
  city = entry.fetch("city")
  payload = entry["extraction_path"] ? JSON.parse(Pathname(entry.fetch("extraction_path")).read) : entry
  fiscal_year_end = Date.iso8601(payload.fetch("fiscal_year_end"))
  asset_sha256 = payload.fetch("asset_sha256")
  document_canonical_id = payload.fetch("document_canonical_id")
  institution_canonical_id = payload["institution_canonical_id"] ||
    release.institution_documents.find_by!(canonical_id: document_canonical_id).institution.canonical_id
  institution = release.institutions.find_by!(canonical_id: institution_canonical_id)

  headline = release.financial_statement_extractions.find_or_initialize_by(
    asset_sha256:,
    extractor_version: Warehouse::FinancialStatementExtraction::Pipeline::EXTRACTOR_VERSION,
    fiscal_year_end:
  )
  unless headline.status == "approved"
    headline.assign_attributes(
      institution_canonical_id:,
      document_canonical_id:,
      fiscal_year_end:,
      statement_basis: "consolidated",
      llm_model: payload["model"] || Warehouse::FinancialStatementExtraction::Pipeline::DEFAULT_MODEL,
      status: "pending"
    )
    headline.save!
    headline_result = headline.extractor.extract(
      pdf_path: entry.fetch("pdf_path"), institution_name: institution.name_en,
      population: entry["population"]
    )
    unless headline_result.status == "extracted"
      results << { city:, fiscal_year: fiscal_year_end.year, status: headline.reload.status,
                   reason: "headline extraction did not pass all deterministic checks" }
      next
    end
  end

  extraction = release.financial_statement_extractions.find_or_initialize_by(
    asset_sha256: headline.asset_sha256,
    extractor_version: Warehouse::FinancialStatementExtraction::DetailedPipeline::EXTRACTOR_VERSION,
    fiscal_year_end:
  )
  if extraction.status == "approved"
    results << { city:, fiscal_year: fiscal_year_end.year, status: "approved",
                 line_items: extraction.financial_statement_line_items.count }
    next
  end
  extraction.assign_attributes(
    institution_canonical_id: headline.institution_canonical_id,
    document_canonical_id: headline.document_canonical_id,
    fiscal_year_end: headline.fiscal_year_end,
    statement_basis: headline.statement_basis,
    language: headline.language,
    llm_model: Warehouse::FinancialStatementExtraction::DetailedPipeline::DEFAULT_MODEL,
    status: "pending"
  )
  extraction.save!
  result = extraction.extractor.extract_detailed(
    pdf_path: entry.fetch("pdf_path"),
    institution_name: institution.name_en,
    population: entry["population"]
  )
  results << {
    city:, fiscal_year: fiscal_year_end.year, status: extraction.reload.status,
    line_items: extraction.financial_statement_line_items.count,
    failed_checks: Array(extraction.check_results).count { |check| check["status"] == "fail" }
  }
rescue => error
  results << { city:, fiscal_year: fiscal_year_end&.year, status: "failed",
               error: "#{error.class}: #{error.message}" }
end

puts JSON.pretty_generate(release: release.version, results:)
