#!/usr/bin/env ruby

require_relative "../config/environment"
require "optparse"

options = {}
OptionParser.new do |parser|
  parser.banner = "Usage: bundle exec ruby script/audit_municipal_financial_facts.rb --config CONFIG.json --output AUDIT.json"
  parser.on("--config PATH") { |value| options[:config] = Pathname(value) }
  parser.on("--output PATH") { |value| options[:output] = Pathname(value) }
end.parse!
abort "--config and --output are required" unless options.values_at(:config, :output).all?

entries = JSON.parse(options.fetch(:config).read).fetch("entries")
results = entries.map do |entry|
  payload = JSON.parse(Pathname(entry.fetch("extraction_path")).read)
  located = Warehouse::FinancialStatementExtraction::PageLocator.new(entry.fetch("pdf_path")).locate
  facts = payload.fetch("facts").map do |fact|
    fact.symbolize_keys.merge(
      value: Warehouse::FinancialStatementExtraction::NumberParser.parse(
        fact.fetch("raw_text"), raw_label: fact.fetch("raw_label"), concept: fact.fetch("concept")
      ) * Integer(fact.fetch("scale")),
      extraction_confidence: BigDecimal(fact.fetch("extraction_confidence").to_s)
    )
  end
  response = payload.fetch("model_response")
  flags = {
    remeasurement_present: response.fetch("remeasurement_present", false),
    operations_adjustment_present: response.fetch("operations_adjustment_present", false),
    rollforward_adjustment_present: response.fetch("rollforward_adjustment_present", false)
  }
  validator = Warehouse::FinancialStatementExtraction::Validator.new(
    facts:, fiscal_year: Date.iso8601(payload.fetch("fiscal_year_end")).year,
    population: entry["population"], page_texts: located.page_texts, flags:
  )
  checks = validator.validate
  original_facts = payload.fetch("facts").index_by { |fact| fact.fetch("concept") }
  {
    city: entry.fetch("city"),
    institution_canonical_id: payload.fetch("institution_canonical_id"),
    fiscal_year_end: payload.fetch("fiscal_year_end"),
    asset_sha256: payload.fetch("asset_sha256"),
    current_status: validator.acceptable?(checks) ? "extracted" : "needs_review",
    fact_count: facts.length,
    exact_value_recomputations: facts.count do |fact|
      BigDecimal(original_facts.fetch(fact.fetch(:concept)).fetch("value")) == fact.fetch(:value)
    end,
    position_page: located.position_page,
    operations_page: located.operations_page,
    failed_checks: checks.select { |check| check[:status] == "fail" },
    skipped_checks: checks.select { |check| check[:status] == "skip" }.map { |check| check[:id] }
  }
end

output = {
  generated_at: Time.current.iso8601,
  extractor_version: Warehouse::FinancialStatementExtraction::Pipeline::EXTRACTOR_VERSION,
  results:
}
FileUtils.mkdir_p(options.fetch(:output).dirname)
options.fetch(:output).write(JSON.pretty_generate(output) << "\n")
puts JSON.pretty_generate(output)
