#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "date"
require "fileutils"
require "json"
require "optparse"
require "pathname"
require "thread"
require "time"

require_relative "scrape_municipal_financial_reports"

class AuditMunicipalFinancialStatementAssets
  DEFAULT_ASSET_ROOT = Pathname("/Volumes/floppy/york_factory/public_institutions/assets")
  VALIDATION_TEXT_BYTES = 1_000_000
  HYBRID_OCR_MAX_PAGES = 75
  HYBRID_OCR_CHUNK_PAGES = 8
  HYBRID_OCR_DPI = 120
  SUBSIDIARY_EXTENSION_MARKERS = %w[conservancy].freeze

  def initialize(manifest_path:, output_path:, audit_path:, audited_at:, threads: 6,
    asset_root: DEFAULT_ASSET_ROOT)
    @manifest_path = Pathname(manifest_path).expand_path
    @output_path = Pathname(output_path).expand_path
    @audit_path = Pathname(audit_path).expand_path
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
    raise "refusing to overwrite #{@audit_path}" if @audit_path.exist?

    manifest = JSON.parse(@manifest_path.read)
    rows = manifest.fetch("municipalities")
    results = parallel_map(rows) { |row| audit_institution(row) }
    rejected = results.flat_map { |result| result.fetch("rejected_assets") }

    results.each do |result|
      row = rows.fetch(result.fetch("index"))
      row["documents"] = result.fetch("documents")
    end
    update_coverage!(manifest, rows)
    manifest["financial_statement_asset_audit"] = {
      "audited_at" => @audited_at.iso8601,
      "source_manifest_path" => @manifest_path.to_s,
      "source_manifest_sha256" => Digest::SHA256.file(@manifest_path).hexdigest,
      "audit_path" => @audit_path.to_s
    }

    audit = {
      "audited_at" => @audited_at.iso8601,
      "source_manifest_path" => @manifest_path.to_s,
      "source_manifest_sha256" => Digest::SHA256.file(@manifest_path).hexdigest,
      "institution_count" => rows.length,
      "institutions_with_financial_statements" => institutions_with_statements(rows),
      "validated_asset_count" => results.sum { |result| result.fetch("validated_asset_count") },
      "rejected_asset_count" => rejected.length,
      "rejected_assets" => rejected
    }
    write_json(@audit_path, audit)
    write_json(@output_path, manifest)
    puts JSON.pretty_generate(audit.except("rejected_assets").merge(
      "output" => @output_path.to_s,
      "audit" => @audit_path.to_s,
      "output_sha256" => Digest::SHA256.file(@output_path).hexdigest,
      "audit_sha256" => Digest::SHA256.file(@audit_path).hexdigest
    ))
  end

  private

  def audit_institution(row)
    validated_count = 0
    rejected = []
    documents = Array(row["documents"]).filter_map do |document|
      next document unless document["document_type"] == "financial-statements"

      valid_assets = Array(document["assets"]).select do |asset|
        validate_asset!(row, document, asset)
        validated_count += 1
        true
      rescue StandardError => error
        rejected << {
          "institution_id" => row.fetch("canonical_id"),
          "document_id" => document.fetch("canonical_id"),
          "content_sha256" => asset["content_sha256"],
          "archive_path" => asset["archive_path"],
          "reason" => error.message
        }
        false
      end
      next if valid_assets.empty?

      normalize_asset_order!(valid_assets)

      document.merge("assets" => valid_assets)
    end
    {
      "index" => row.fetch("__audit_index"),
      "documents" => documents,
      "validated_asset_count" => validated_count,
      "rejected_assets" => rejected
    }
  end

  def normalize_asset_order!(assets)
    assets.each_with_index do |asset, index|
      asset["preferred"] = index.zero?
      if assets.length > 1
        asset["part_index"] = index + 1
        asset["part_count"] = assets.length
      else
        asset["part_index"] = nil if asset.key?("part_index")
        asset["part_count"] = nil if asset.key?("part_count")
      end
    end
  end

  def validate_asset!(row, document, asset)
    relative = asset.fetch("archive_path")
    path = @asset_root.join(relative)
    raise "archived file is missing" unless path.file?

    bytes = path.binread
    expected_hash = asset.fetch("content_sha256")
    raise "SHA-256 mismatch" unless Digest::SHA256.hexdigest(bytes) == expected_hash
    raise "file is not a PDF" unless bytes.start_with?("%PDF-")

    # The incremental fallback below owns OCR page selection. Suppressing the
    # scraper's five-page convenience fallback prevents pages 1-5 from being
    # rendered and recognized twice for fully scanned PDFs.
    text = @scraper.send(:pdf_text, bytes, max_pages: nil, fallback_to_ocr: false)
    official_name = @scraper.send(:official_name, row)
    institution_match = institution_matches_row?(text, row, official_name)

    candidate = {
      "label" => document["title"] || document["title_en"] || "",
      "url" => document["download_url"].to_s
    }
    types = document_types(text, candidate)
    content_year = @scraper.send(:financial_statement_fiscal_year, text, max_bytes: VALIDATION_TEXT_BYTES)
    unless institution_match && types.include?("financial-statements") && content_year
      text = incremental_ocr_text(bytes, text, official_name, candidate, row)
      institution_match = institution_matches_row?(text, row, official_name)
      types = document_types(text, candidate)
      content_year = @scraper.send(:financial_statement_fiscal_year, text, max_bytes: VALIDATION_TEXT_BYTES)
    end
    raise "PDF text did not identify #{official_name}" unless institution_match
    if subsidiary_issuer_extension?(text, official_name)
      raise "PDF audited issuer is a distinct legal entity extending #{official_name}"
    end
    raise "PDF is not the municipality's audited financial statement" unless types.include?("financial-statements")

    expected_year = document_fiscal_year(document)
    raise "document metadata has no fiscal year" unless expected_year

    raise "PDF text did not identify its fiscal year" unless content_year
    return if content_year == expected_year

    raise "PDF fiscal year #{content_year} does not match document fiscal year #{expected_year}"
  end

  def incremental_ocr_text(bytes, embedded_text, official_name, candidate, row)
    page_limit = [ @scraper.send(:pdf_page_count, bytes), HYBRID_OCR_MAX_PAGES ].min
    chunks = []
    (1..page_limit).step(HYBRID_OCR_CHUNK_PAGES) do |first_page|
      last_page = [ first_page + HYBRID_OCR_CHUNK_PAGES - 1, page_limit ].min
      chunks << @scraper.send(
        :ocr_pdf_text,
        bytes,
        first_page: first_page,
        last_page: last_page,
        dpi: HYBRID_OCR_DPI,
        allow_empty: true
      )
      # Put bounded OCR first so it remains inside the validation byte window
      # even when the PDF also contains a large unrelated text layer.
      combined = "#{chunks.join("\f")}\f#{embedded_text}"
      return combined if complete_financial_statement_evidence?(combined, official_name, candidate, row)
    end

    "#{chunks.join("\f")}\f#{embedded_text}"
  end

  def complete_financial_statement_evidence?(text, official_name, candidate, row)
    institution_matches_row?(text, row, official_name) &&
      document_types(text, candidate).include?("financial-statements") &&
      @scraper.send(:financial_statement_fiscal_year, text, max_bytes: VALIDATION_TEXT_BYTES)
  end

  def institution_matches_row?(text, row, official_name)
    return true if @scraper.send(:institution_matches?, text, official_name)
    return false unless row.fetch("canonical_id").start_with?("ca/qc/")

    geography_code = Array(row["identifiers"]).find do |identifier|
      identifier["scheme"] == "qc.code-geographique"
    end&.fetch("value", nil).to_s
    return false unless geography_code.match?(/\A\d{5}\z/)

    # Quebec's standardized municipal financial reports carry the stable MAMH
    # geographic code on the cover. This is stronger historical issuer evidence
    # than today's name when a municipality was renamed without changing code.
    opening = @scraper.send(:normalize, safe_byteslice(text, 20_000))
    opening.match?(/\bcode geographique\s+#{Regexp.escape(geography_code)}\b/)
  end

  def document_types(text, candidate)
    evidence = "#{candidate.fetch('label')} #{candidate.fetch('url')} " \
      "#{safe_byteslice(text, VALIDATION_TEXT_BYTES)}"
    @scraper.send(:document_types, evidence, candidate)
  end

  def subsidiary_issuer_extension?(text, official_name)
    normalized_name = @scraper.send(:normalize, official_name)
    return false if SUBSIDIARY_EXTENSION_MARKERS.any? { |marker| normalized_name.split.include?(marker) }

    opening = @scraper.send(:normalize, safe_byteslice(text, 20_000))
    audited_issuer = text.match(
      /we\s+have\s+audited\s+the(?:\s+accompanying)?(?:\s+consolidated)?\s+financial\s+statements\s+of\s+(.{0,240})/im
    )&.captures&.first
    normalized_audited_issuer = @scraper.send(:normalize, audited_issuer.to_s)
    SUBSIDIARY_EXTENSION_MARKERS.any? do |marker|
      extended_name = "#{normalized_name} #{marker}"
      opening.match?(/\b#{Regexp.escape(extended_name)}\b/) ||
        normalized_audited_issuer.match?(/\b#{Regexp.escape(extended_name)}\b/)
    end
  end

  def safe_byteslice(text, max_bytes)
    text.to_s.byteslice(0, max_bytes).to_s.force_encoding(Encoding::UTF_8).scrub
  end

  def document_fiscal_year(document)
    canonical_year = document.fetch("canonical_id")[
      %r{/financial-statements/(19\d{2}|20\d{2})(?:/|\z)}, 1
    ]&.to_i
    fiscal_period_end = document["fiscal_period_end"]
    fiscal_year = Date.iso8601(fiscal_period_end).year if fiscal_period_end
    if canonical_year && fiscal_year && canonical_year != fiscal_year
      raise "document canonical and fiscal years disagree: #{canonical_year} != #{fiscal_year}"
    end

    fiscal_year || canonical_year
  rescue Date::Error
    nil
  end

  def parallel_map(rows)
    rows.each_with_index { |row, index| row["__audit_index"] = index }
    queue = Queue.new
    rows.each { |row| queue << row }
    results = []
    mutex = Mutex.new
    Array.new(@threads) do
      Thread.new do
        loop do
          row = queue.pop(true)
          result = audit_institution(row)
          mutex.synchronize { results << result }
        rescue ThreadError
          break
        end
      end
    end.each(&:join)
    rows.each { |row| row.delete("__audit_index") }
    results.sort_by { |result| result.fetch("index") }
  end

  def update_coverage!(manifest, rows)
    count = institutions_with_statements(rows)
    coverage = manifest.fetch("coverage")
    row = coverage.find { |item| item["subject"] == "financial-statements" }
    if row
      row["status"] = count == rows.length ? "complete" : "partial"
      row["notes"] = "#{count} of #{rows.length} institutions have at least one locally archived, " \
        "SHA-256-verified municipal audited financial statement after content revalidation."
    end

    assets = rows.sum do |institution|
      Array(institution["documents"]).sum { |document| Array(document["assets"]).length }
    end
    asset_row = coverage.find { |item| item["subject"] == "document-assets" }
    asset_row["notes"] = "#{assets} SHA-256-addressed document assets are linked across the manifest." if asset_row
  end

  def institutions_with_statements(rows)
    rows.count do |row|
      Array(row["documents"]).any? do |document|
        document["document_type"] == "financial-statements" && Array(document["assets"]).any?
      end
    end
  end

  def write_json(path, payload)
    FileUtils.mkdir_p(path.dirname)
    path.write(JSON.pretty_generate(payload) << "\n")
  end
end

if $PROGRAM_NAME == __FILE__
  options = { threads: 6 }
  OptionParser.new do |parser|
    parser.banner = "Usage: audit_municipal_financial_statement_assets.rb --manifest PATH --output PATH --audit PATH --audited-at ISO8601"
    parser.on("--manifest PATH") { |value| options[:manifest_path] = value }
    parser.on("--output PATH") { |value| options[:output_path] = value }
    parser.on("--audit PATH") { |value| options[:audit_path] = value }
    parser.on("--audited-at TIME") { |value| options[:audited_at] = value }
    parser.on("--threads N", Integer) { |value| options[:threads] = value }
    parser.on("--asset-root PATH") { |value| options[:asset_root] = Pathname(value) }
  end.parse!

  missing = %i[manifest_path output_path audit_path audited_at].reject { |key| options[key] }
  abort "missing options: #{missing.join(', ')}" if missing.any?

  AuditMunicipalFinancialStatementAssets.new(**options).run
end
