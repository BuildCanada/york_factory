#!/usr/bin/env ruby

require_relative "../config/environment"
require "optparse"

options = {}
OptionParser.new do |parser|
  parser.banner = "Usage: bin/rails runner script/import_municipal_financial_pilot.rb --release VERSION --config PATH --audit PATH"
  parser.on("--release VERSION") { |value| options[:release] = value }
  parser.on("--config PATH") { |value| options[:config] = Pathname(value).expand_path }
  parser.on("--audit PATH") { |value| options[:audit] = Pathname(value).expand_path }
end.parse!
missing = %i[release config audit].reject { |key| options[key].present? }
abort "missing options: #{missing.join(', ')}" if missing.any?

release = Warehouse::InstitutionRelease.find_by!(version: options.fetch(:release))
config = JSON.parse(options.fetch(:config).read)
audit = JSON.parse(options.fetch(:audit).read).fetch("results").index_by { |row| row.fetch("city") }
imported = []
skipped = []

config.fetch("entries").each do |entry|
  city = entry.fetch("city")
  validation = audit.fetch(city)
  unless validation.fetch("current_status") == "extracted" && validation.fetch("failed_checks").empty?
    raise "#{city} did not pass the pinned validator audit"
  end

  payload = JSON.parse(Pathname(entry.fetch("extraction_path")).read)
  asset = release.institution_document_assets.find_by(content_sha256: payload.fetch("asset_sha256"))
  unless asset
    skipped << { city:, reason: "asset is absent from the final release" }
    next
  end
  document = asset.institution_document
  extraction = release.financial_statement_extractions.find_or_initialize_by(
    asset_sha256: payload.fetch("asset_sha256"), extractor_version: payload.fetch("extractor_version")
  )
  next imported << city if extraction.status == "approved"

  extraction.assign_attributes(
    institution_canonical_id: document.institution.canonical_id,
    document_canonical_id: document.canonical_id,
    fiscal_year_end: Date.iso8601(payload.fetch("fiscal_year_end")),
    statement_basis: payload.fetch("statement_basis"), language: payload.fetch("language"),
    llm_model: payload.fetch("model"), status: "extracted", check_results: payload.fetch("checks"),
    llm_response_snapshot: payload.fetch("model_response")
  )
  extraction.transaction do
    extraction.save!
    extraction.financial_statement_facts.delete_all
    payload.fetch("facts").each do |fact|
      extraction.financial_statement_facts.create!(
        concept: fact.fetch("concept"), value: BigDecimal(fact.fetch("value")),
        raw_text: fact.fetch("raw_text"), raw_label: fact.fetch("raw_label"),
        scale: fact.fetch("scale"), statement: fact.fetch("statement"),
        source_page: fact.fetch("source_page"), column_year: fact.fetch("column_year"),
        extraction_confidence: fact.fetch("extraction_confidence")
      )
    end
    extraction.approve!(
      reviewer: "local-pilot-validator",
      notes: "Local preview only; imported from pinned independent validator audit #{options.fetch(:audit)}"
    )
  end
  imported << city
end

puts JSON.pretty_generate(
  release: release.version, imported_cities: imported, imported_count: imported.length,
  skipped: skipped, skipped_count: skipped.length
)
