#!/usr/bin/env ruby

require_relative "../config/environment"
require "optparse"

class MunicipalFinancialFactsCli
  REQUIRED = %i[pdf institution_id institution_name document_id sha256 fiscal_year_end output].freeze

  def initialize(argv)
    @options = { model: Warehouse::FinancialStatementExtraction::Pipeline::DEFAULT_MODEL }
    parser.parse!(argv)
    missing = REQUIRED.reject { |key| @options[key].present? }
    raise OptionParser::MissingArgument, missing.join(", ") if missing.any?
  end

  def run
    result = Warehouse::FinancialStatementExtraction::Pipeline.new(
      pdf_path: @options.fetch(:pdf),
      institution_canonical_id: @options.fetch(:institution_id),
      institution_name: @options.fetch(:institution_name),
      document_canonical_id: @options.fetch(:document_id),
      asset_sha256: @options.fetch(:sha256),
      fiscal_year_end: Date.iso8601(@options.fetch(:fiscal_year_end)),
      population: @options[:population],
      model: @options.fetch(:model)
    ).run
    write_output(success_payload(result))
    puts "#{@options.fetch(:institution_id)}: #{result.status} -> #{@options.fetch(:output)}"
    result.status == "extracted" ? 0 : 2
  rescue => error
    write_output(failure_payload(error)) if @options[:output]
    warn "#{error.class}: #{error.message}"
    1
  end

  private

  def parser
    @parser ||= OptionParser.new do |options|
      options.banner = "Usage: bundle exec ruby script/extract_municipal_financial_facts.rb [options]"
      options.on("--pdf PATH") { |value| @options[:pdf] = value }
      options.on("--institution-id ID") { |value| @options[:institution_id] = value }
      options.on("--institution-name NAME") { |value| @options[:institution_name] = value }
      options.on("--document-id ID") { |value| @options[:document_id] = value }
      options.on("--sha256 SHA") { |value| @options[:sha256] = value }
      options.on("--fiscal-year-end DATE") { |value| @options[:fiscal_year_end] = value }
      options.on("--population NUMBER", Float) { |value| @options[:population] = value }
      options.on("--model MODEL") { |value| @options[:model] = value }
      options.on("--output PATH") { |value| @options[:output] = value }
    end
  end

  def success_payload(result)
    {
      schema_version: "1.0",
      extractor_version: Warehouse::FinancialStatementExtraction::Pipeline::EXTRACTOR_VERSION,
      generated_at: Time.current.iso8601,
      institution_canonical_id: @options.fetch(:institution_id),
      document_canonical_id: @options.fetch(:document_id),
      asset_sha256: @options.fetch(:sha256),
      fiscal_year_end: @options.fetch(:fiscal_year_end),
      model: @options.fetch(:model),
      status: result.status,
      language: result.language,
      statement_basis: result.statement_basis,
      located_pages: {
        financial_position: result.locator_result.position_page,
        operations: result.locator_result.operations_page,
        candidate_pages: result.locator_result.candidate_pages,
        ocr_pages: result.locator_result.ocr_pages
      },
      facts: result.facts.map { |fact| fact.transform_values { |value| value.is_a?(BigDecimal) ? value.to_s("F") : value } },
      checks: result.checks,
      prompt_sha256: Digest::SHA256.hexdigest(result.prompt),
      model_response: result.response
    }
  end

  def failure_payload(error)
    {
      schema_version: "1.0",
      extractor_version: Warehouse::FinancialStatementExtraction::Pipeline::EXTRACTOR_VERSION,
      generated_at: Time.current.iso8601,
      institution_canonical_id: @options[:institution_id],
      document_canonical_id: @options[:document_id],
      asset_sha256: @options[:sha256],
      fiscal_year_end: @options[:fiscal_year_end],
      status: "failed",
      error: "#{error.class}: #{error.message}"
    }
  end

  def write_output(payload)
    path = Pathname(@options.fetch(:output))
    FileUtils.mkdir_p(path.dirname)
    path.write(JSON.pretty_generate(payload) << "\n")
  end
end

exit MunicipalFinancialFactsCli.new(ARGV).run if $PROGRAM_NAME == __FILE__
