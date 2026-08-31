#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "optparse"
require "pathname"
require "time"

require_relative "scrape_municipal_financial_reports"

class ArchiveExplicitMunicipalFinancialReports
  EXPLICIT_PROVENANCE_FIELDS = %w[original_url wayback_timestamp wayback_digest].freeze

  def initialize(manifest_path:, input_path:, output_path:, retrieved_at:)
    @manifest_path = Pathname(manifest_path).expand_path
    @input_path = Pathname(input_path).expand_path
    @output_path = Pathname(output_path).expand_path
    @retrieved_at = Time.iso8601(retrieved_at).utc
    @scraper = MunicipalFinancialReportScraper.new(
      manifest_path: @manifest_path,
      output_dir: @output_path.dirname,
      retrieved_at: @retrieved_at.iso8601
    )
  end

  def run
    raise "refusing to overwrite #{@output_path}" if @output_path.exist?

    manifest = JSON.parse(@manifest_path.read)
    rows = manifest.fetch("municipalities").to_h { |row| [ row.fetch("canonical_id"), row ] }
    requested = JSON.parse(@input_path.read).fetch("reports")
    grouped = requested.group_by { |report| report.fetch("canonical_id") }
    institutions = grouped.sort.map do |canonical_id, reports|
      archive_institution(rows.fetch(canonical_id), reports)
    end
    archived = institutions.flat_map { |institution| institution.fetch("reports") }
    payload = {
      "batch" => "explicit-municipal-financial-reports",
      "source_manifest" => @manifest_path.to_s,
      "source_manifest_sha256" => Digest::SHA256.file(@manifest_path).hexdigest,
      "source_input" => @input_path.to_s,
      "source_input_sha256" => Digest::SHA256.file(@input_path).hexdigest,
      "retrieved_at" => @retrieved_at.iso8601,
      "institution_count" => institutions.length,
      "institutions_with_reports" => institutions.count { |institution| institution.fetch("reports").any? },
      "validated_report_count" => archived.length,
      "financial_statement_count" => archived.count { |report| report.fetch("document_type") == "financial-statements" },
      "annual_report_count" => archived.count { |report| report.fetch("document_type") == "annual-report" },
      "sofi_count" => archived.count do |report|
        report.fetch("document_type") == "statement-of-financial-information"
      end,
      "institutions" => institutions
    }
    FileUtils.mkdir_p(@output_path.dirname)
    @output_path.write(JSON.pretty_generate(payload) << "\n")
    puts JSON.pretty_generate(payload.slice(
      "institution_count", "institutions_with_reports", "validated_report_count",
      "financial_statement_count", "annual_report_count", "sofi_count"
    ))
    puts "output=#{@output_path}"
    puts "sha256=#{Digest::SHA256.file(@output_path).hexdigest}"
  end

  private

  def archive_institution(row, requested)
    errors = []
    reports = requested.flat_map do |report|
      candidate = candidate_for(report)
      @scraper.send(:verify_and_archive, row, candidate)
    rescue StandardError => error
      errors << "#{report.fetch('download_url')}: #{error.message}"
      []
    end
    reports.uniq! { |report| [ report.fetch("document_type"), report.fetch("year"), report.fetch("content_sha256") ] }
    reports.sort_by! { |report| [ report.fetch("document_type"), report.fetch("year"), report.fetch("download_url") ] }
    {
      "canonical_id" => row.fetch("canonical_id"),
      "official_name" => @scraper.send(:official_name, row),
      "website_url" => row.fetch("website_url"),
      "searched_locations" => requested.flat_map { |report| [ report["source_page_url"], report["download_url"] ] }.uniq,
      "candidate_count" => requested.length,
      "validated_report_count" => reports.length,
      "reports" => reports,
      "gaps" => errors.empty? ? [] : [ "One or more explicit report URLs failed validation." ],
      "discovery_errors" => [],
      "candidate_errors" => errors
    }
  end

  def candidate_for(report)
    report.slice(*EXPLICIT_PROVENANCE_FIELDS).merge(
      "url" => report.fetch("download_url"),
      "label" => report.fetch("label"),
      "source_page_url" => report.fetch("source_page_url")
    )
  end
end

if $PROGRAM_NAME == __FILE__
  options = {}
  OptionParser.new do |parser|
    parser.banner = "Usage: archive_explicit_municipal_financial_reports.rb --manifest PATH --input PATH " \
      "--output PATH --retrieved-at ISO8601"
    parser.on("--manifest PATH") { |value| options[:manifest_path] = value }
    parser.on("--input PATH") { |value| options[:input_path] = value }
    parser.on("--output PATH") { |value| options[:output_path] = value }
    parser.on("--retrieved-at ISO8601") { |value| options[:retrieved_at] = value }
  end.parse!

  missing = %i[manifest_path input_path output_path retrieved_at].reject { |key| options[key] }
  abort "missing options: #{missing.join(', ')}" if missing.any?

  ArchiveExplicitMunicipalFinancialReports.new(**options).run
end
