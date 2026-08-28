#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "optparse"
require "pathname"
require "thread"
require "time"
require_relative "scrape_municipal_financial_reports"

class PromoteEmbeddedMunicipalFinancialStatements
  CONTAINER_TYPES = %w[annual-report statement-of-financial-information].freeze

  def initialize(manifest_path:, output_path:, audited_at:, threads: 6,
    asset_root: MunicipalFinancialReportScraper::DEFAULT_ASSET_ROOT)
    @manifest_path = Pathname(manifest_path).expand_path
    @output_path = Pathname(output_path).expand_path
    @audited_at = Time.iso8601(audited_at).utc
    @threads = Integer(threads)
    @asset_root = Pathname(asset_root).expand_path
    @scraper = MunicipalFinancialReportScraper.new(
      manifest_path: @manifest_path,
      output_dir: @output_path.dirname,
      retrieved_at: @audited_at.iso8601,
      asset_root: @asset_root
    )
  end

  def run
    raise "refusing to overwrite #{@output_path}" if @output_path.exist?

    manifest = JSON.parse(@manifest_path.read)
    candidates = manifest.fetch("municipalities")
    results = parallel_map(candidates) { promote_institution(_1) }
    reports = results.flat_map { _1.fetch("reports") }
    payload = {
      "batch" => "#{manifest.fetch('province').fetch('code')}-embedded-municipal-financial-statements",
      "source_manifest" => @manifest_path.to_s,
      "source_manifest_sha256" => Digest::SHA256.file(@manifest_path).hexdigest,
      "audited_at" => @audited_at.iso8601,
      "institution_count" => results.length,
      "institutions_with_reports" => results.count { _1.fetch("reports").any? },
      "validated_report_count" => reports.length,
      "financial_statement_count" => reports.length,
      "annual_report_count" => 0,
      "sofi_count" => 0,
      "institutions" => results
    }
    @output_path.dirname.mkpath
    @output_path.write(JSON.pretty_generate(payload) << "\n")
    puts JSON.pretty_generate(payload.slice(
      "institution_count", "institutions_with_reports", "validated_report_count",
      "financial_statement_count"
    ).merge("output" => @output_path.to_s, "sha256" => Digest::SHA256.file(@output_path).hexdigest))
  end

  private

  def promote_institution(row)
    errors = []
    existing_reports = existing_financial_statement_keys(row)
    reports = Array(row["documents"]).select { CONTAINER_TYPES.include?(_1["document_type"]) }.flat_map do |document|
      Array(document["assets"]).filter_map do |asset|
        report = promote_asset(row, document, asset)
        report unless existing_reports.include?([ report.fetch("year"), report.fetch("content_sha256") ])
      rescue StandardError => error
        errors << "#{document.fetch('canonical_id')}: #{asset['archive_path']}: #{error.class}: #{error.message}"
        nil
      end
    end
    reports.uniq! { [ _1.fetch("year"), _1.fetch("content_sha256") ] }
    reports.sort_by! { [ _1.fetch("year"), _1.fetch("download_url") ] }
    {
      "canonical_id" => row.fetch("canonical_id"),
      "official_name" => official_name(row),
      "website_url" => row["website_url"],
      "searched_locations" => [],
      "candidate_count" => Array(row["documents"]).sum do |document|
        CONTAINER_TYPES.include?(document["document_type"]) ? Array(document["assets"]).length : 0
      end,
      "validated_report_count" => reports.length,
      "reports" => reports,
      "gaps" => reports.empty? ? [ "No archived annual-report or SOFI container included a validated municipal audited statement." ] : [],
      "discovery_errors" => [],
      "candidate_errors" => errors,
      "review_rejections" => []
    }
  end

  def promote_asset(row, document, asset)
    relative_path = asset.fetch("archive_path")
    path = @asset_root.join(relative_path)
    raise "archived file is missing" unless path.file?

    bytes = path.binread
    raise "SHA-256 mismatch" unless Digest::SHA256.hexdigest(bytes) == asset.fetch("content_sha256")
    raise "file is not a PDF" unless bytes.start_with?("%PDF-")

    text = @scraper.send(:pdf_text, bytes, max_pages: nil)
    name = official_name(row)
    raise "PDF text did not identify #{name}" unless @scraper.send(:institution_matches?, text, name)

    candidate = {
      "label" => document["title"] || document["title_en"] || "",
      "url" => document["download_url"].to_s,
      "source_page_url" => document["source_page_url"].to_s
    }
    evidence = "#{candidate.fetch('label')} #{candidate.fetch('url')} #{text}"
    types = @scraper.send(:document_types, evidence, candidate)
    raise "container does not include the municipality's audited financial statements" unless types.include?("financial-statements")

    year = @scraper.send(:report_year, candidate, text)
    raise "reporting year could not be determined" unless year

    asset.slice(
      "content_sha256", "byte_size", "mime_type", "archive_path", "asset_role",
      "preferred", "retrieved_at", "rights_status"
    ).merge(
      "document_type" => "financial-statements",
      "year" => year,
      "title" => "#{name} Audited Financial Statements — #{year}",
      "source_page_url" => document["source_page_url"],
      "download_url" => document["download_url"] || asset["download_url"],
      "languages" => @scraper.send(:source_languages, text),
      "retrieved_at" => asset["retrieved_at"] || @audited_at.iso8601,
      "rights_status" => asset["rights_status"] || "metadata_only",
      "verification" => {
        "institution_name_in_pdf" => true,
        "document_type_from_full_pdf_text" => true,
        "embedded_in_document_id" => document.fetch("canonical_id"),
        "embedded_in_document_type" => document.fetch("document_type"),
        "pdf_text_sha256" => Digest::SHA256.hexdigest(text)
      }
    )
  end

  def existing_financial_statement_keys(row)
    Array(row["documents"]).filter_map do |document|
      next unless document["document_type"] == "financial-statements"

      Array(document["assets"]).filter_map do |asset|
        year = document["year"] || asset["year"] || document_year(document)
        sha256 = asset["content_sha256"]
        [ Integer(year), sha256 ] if year && sha256
      rescue ArgumentError, TypeError
        nil
      end
    end.flatten(1).to_h { [ _1, true ] }
  end

  def document_year(document)
    document["canonical_id"].to_s[%r{/financial-statements/((?:19|20)\d{2})(?:/|\z)}, 1]&.to_i
  end

  def official_name(row)
    row["official_name_en"] || row["official_name"] || row.fetch("official_name_fr")
  end

  def parallel_map(rows)
    queue = Queue.new
    rows.each_with_index { |row, index| queue << [ index, row ] }
    results = Array.new(rows.length)
    Array.new(@threads) do
      Thread.new do
        loop do
          index, row = queue.pop(true)
          results[index] = yield(row)
        rescue ThreadError
          break
        end
      end
    end.each(&:join)
    results
  end
end

if $PROGRAM_NAME == __FILE__
  options = { threads: 6 }
  OptionParser.new do |parser|
    parser.banner = "Usage: promote_embedded_municipal_financial_statements.rb --manifest PATH --output PATH --audited-at ISO8601"
    parser.on("--manifest PATH") { options[:manifest_path] = _1 }
    parser.on("--output PATH") { options[:output_path] = _1 }
    parser.on("--audited-at TIME") { options[:audited_at] = _1 }
    parser.on("--threads N", Integer) { options[:threads] = _1 }
    parser.on("--asset-root PATH") { options[:asset_root] = Pathname(_1) }
  end.parse!

  missing = %i[manifest_path output_path audited_at].reject { options[_1] }
  abort "missing options: #{missing.join(', ')}" if missing.any?

  PromoteEmbeddedMunicipalFinancialStatements.new(**options).run
end
