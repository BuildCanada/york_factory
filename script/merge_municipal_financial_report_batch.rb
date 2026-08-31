#!/usr/bin/env ruby
# frozen_string_literal: true

require "cgi"
require "digest"
require "fileutils"
require "json"
require "optparse"
require "pathname"
require "uri"

class MergeMunicipalFinancialReportBatch
  PROVINCIALLY_ADMINISTERED_JURISDICTION_TYPES = %w[local_service_district rural_district].freeze
  YEAR_PATTERN = /(?<!\d)(19[89]\d|20\d{2})(?!\d)/
  TYPE_LABELS = {
    "annual-report" => "Annual Report",
    "financial-statements" => "Audited Financial Statements",
    "statement-of-financial-information" => "Statement of Financial Information"
  }.freeze
  TYPE_LABELS_FR = {
    "annual-report" => "Rapport annuel",
    "financial-statements" => "États financiers audités",
    "statement-of-financial-information" => "État de l’information financière"
  }.freeze

  def initialize(manifest_path:, batch_path:, output_path:)
    @manifest_path = Pathname(manifest_path).expand_path
    @batch_path = Pathname(batch_path).expand_path
    @output_path = Pathname(output_path).expand_path
  end

  def run
    raise "refusing to overwrite #{@output_path}" if @output_path.exist?

    manifest = JSON.parse(@manifest_path.read)
    batch = JSON.parse(@batch_path.read)
    @reviewed_batch = verify_review_provenance!(batch)
    institutions = manifest.fetch("municipalities").to_h { |row| [ row.fetch("canonical_id"), row ] }
    imported = 0
    batch.fetch("institutions").each do |result|
      row = institutions.fetch(result.fetch("canonical_id"))
      imported += merge_reports!(row, result.fetch("reports"))
    end
    update_coverage!(manifest, batch, imported)
    update_audit!(manifest, batch)
    manifest["financial_report_batch"] = file_record(@batch_path)
    write_output(manifest, batch, imported)
  end

  private

  def merge_reports!(row, reports)
    corrected = reports.map { |report| report.merge("year" => corrected_year(report)) }
    grouped = corrected.group_by { |report| [ report.fetch("document_type"), report.fetch("year") ] }
    existing = Array(row["documents"]).to_h { |document| [ document.fetch("canonical_id"), document ] }

    grouped.each do |(type, year), matches|
      canonical_id = "#{row.fetch('canonical_id')}/documents/#{type}/#{year}/general"
      languages = matches.flat_map { |report| report.fetch("languages", []) }.uniq.sort
      title_en = document_title(row["official_name_en"], TYPE_LABELS.fetch(type), year) if languages.include?("en")
      title_fr = document_title(row["official_name_fr"], TYPE_LABELS_FR.fetch(type), year) if languages.include?("fr")
      title_en ||= document_title(row["official_name_en"], TYPE_LABELS.fetch(type), year) unless title_fr
      title_fr ||= document_title(row["official_name_fr"], TYPE_LABELS_FR.fetch(type), year) unless title_en
      document = existing[canonical_id] ||= {
        "canonical_id" => canonical_id,
        "document_type" => type,
        "document_variant" => "general",
        "title" => title_en,
        "title_fr" => title_fr,
        "source_languages" => languages.any? ? languages : row.fetch("source_languages", [ "en" ]),
        "fiscal_period_start" => nil,
        "fiscal_period_end" => nil,
        "published_on" => nil,
        "source_page_url" => matches.first.fetch("source_page_url"),
        "download_url" => matches.first.fetch("download_url"),
        "notes" => "PDF content validated against the reporting institution and document type.",
        "assets" => []
      }
      merge_assets!(document, matches)
    end

    row["documents"] = existing.values.sort_by { |document| document.fetch("canonical_id") }
    grouped.length
  end

  def document_title(name, type_label, year)
    "#{name} #{type_label} — #{year}" if name.to_s.match?(/\S/)
  end

  def merge_assets!(document, reports)
    assets = Array(document["assets"])
    reports.uniq { |report| report.fetch("content_sha256") }.each do |report|
      next if assets.any? { |asset| asset.fetch("content_sha256") == report.fetch("content_sha256") }

      assets << {
        "content_sha256" => report.fetch("content_sha256"),
        "asset_role" => "primary",
        "part_index" => nil,
        "part_count" => nil,
        "preferred" => assets.empty?,
        "download_url" => report.fetch("download_url"),
        "retrieved_at" => report.fetch("retrieved_at"),
        "archive_path" => report.fetch("archive_path"),
        "mime_type" => report.fetch("mime_type"),
        "byte_size" => report.fetch("byte_size"),
        "rights_status" => report.fetch("rights_status", "metadata_only"),
        "page_locator" => nil,
        "languages" => report.fetch("languages", []),
        "verification" => report["verification"]
      }
    end
    if assets.length > 1
      assets.each_with_index do |asset, index|
        asset["part_index"] = index + 1
        asset["part_count"] = assets.length
        asset["preferred"] = index.zero?
      end
    end
    document["assets"] = assets
  end

  def corrected_year(report)
    return Integer(report.fetch("year")) if @reviewed_batch

    # A report extracted from a dated official disclosure bundle inherits the
    # bundle's publication year in its URL, not the statement's fiscal year.
    return Integer(report.fetch("year")) if report.dig("verification", "split_page_range_verified")

    [ url_basename(report["download_url"]), url_basename(report["source_page_url"]), report["title"] ].each do |source|
      years = source.to_s.scan(YEAR_PATTERN).flatten.map(&:to_i).select { |year| year.between?(1980, 2100) }
      return years.first if years.any?
    end
    Integer(report.fetch("year"))
  end

  def verify_review_provenance!(batch)
    review = batch["review"]
    return false unless review

    input_path = Pathname(review.fetch("input_path")).expand_path
    raise "review source batch is missing: #{input_path}" unless input_path.file?

    actual_sha = Digest::SHA256.file(input_path).hexdigest
    raise "review source SHA-256 does not match: #{input_path}" unless actual_sha == review.fetch("input_sha256")

    true
  end

  def url_basename(url)
    CGI.unescape(File.basename(URI(url).path))
  rescue URI::InvalidURIError, TypeError
    ""
  end

  def update_coverage!(manifest, batch, imported)
    rows = manifest.fetch("coverage")
    institutions = manifest.fetch("municipalities")
    financial_scope = institutions.reject do |row|
      PROVINCIALLY_ADMINISTERED_JURISDICTION_TYPES.include?(row["municipality_type"])
    end
    excluded_financial_jurisdictions = institutions.length - financial_scope.length
    financial_institutions = financial_scope.count { |row| has_archived_document?(row, "financial-statements") }
    financial_assets = archived_asset_count(financial_scope, "financial-statements")
    annual_institutions = institutions.count { |row| has_archived_document?(row, "annual-report") }
    annual_assets = archived_asset_count(institutions, "annual-report")
    all_assets = institutions.sum do |row|
      Array(row["documents"]).sum { |document| Array(document["assets"]).length }
    end
    financial = coverage_row(rows, manifest, "financial-statements")
    financial["status"] = financial_institutions == financial_scope.length ? "complete" : "partial"
    financial["notes"] = "#{financial_institutions} of #{financial_scope.length} financial-reporting institutions have " \
      "#{financial_assets} locally archived financial-statement assets after importing #{imported} document works " \
      "from batch #{@batch_path.basename}. #{excluded_financial_jurisdictions} unincorporated, provincially administered " \
      "jurisdictions are retained in the ontology but excluded from this denominator."
    financial["source_url"] = batch["source_url"]

    assets = coverage_row(rows, manifest, "document-assets")
    assets["status"] = "partial"
    assets["notes"] = "#{all_assets} SHA-256-addressed document assets are linked across the manifest."
    assets["source_url"] = batch["source_url"]

    annual = coverage_row(rows, manifest, "annual-reports")
    annual["status"] = annual_institutions == institutions.length ? "complete" : "partial"
    annual["notes"] = "#{annual_institutions} of #{institutions.length} institutions have " \
      "#{annual_assets} locally archived annual-report assets."
    annual["source_url"] = batch["source_url"]
  end

  def has_archived_document?(row, type)
    Array(row["documents"]).any? do |document|
      document["document_type"] == type && Array(document["assets"]).any?
    end
  end

  def archived_asset_count(institutions, type)
    institutions.sum do |row|
      Array(row["documents"]).select { _1["document_type"] == type }.sum do |document|
        Array(document["assets"]).length
      end
    end
  end

  def coverage_row(rows, manifest, subject)
    rows.find { |row| row.fetch("subject") == subject } || begin
      row = {
        "scope_id" => "ca/#{manifest.fetch('province').fetch('code')}",
        "subject" => subject,
        "status" => "not-searched",
        "notes" => "No coverage statement was supplied by the source manifest.",
        "source_url" => nil
      }
      rows << row
      row
    end
  end

  def update_audit!(manifest, batch)
    manifest["scrape_audit"] ||= { "batches" => [], "institutions" => {} }
    audit = manifest.fetch("scrape_audit")
    audit["batches"] ||= []
    institution_audits = audit["institutions"] || audit["municipalities"]
    institution_audits ||= audit["institutions"] = {}
    audit["batches"] << file_record(@batch_path).merge(
      "batch" => batch.fetch("batch"), "retrieved_at" => batch["retrieved_at"] || batch.fetch("audited_at")
    )
    batch.fetch("institutions").each do |result|
      institution_audits[result.fetch("canonical_id")] ||= []
      institution_audits[result.fetch("canonical_id")] << {
        "batch" => @batch_path.basename.to_s,
        "searched_locations" => result.fetch("searched_locations"),
        "gaps" => result.fetch("gaps"),
        "candidate_count" => result.fetch("candidate_count"),
        "validated_report_count" => result.fetch("validated_report_count")
      }
    end
  end

  def file_record(path)
    {
      "path" => path.to_s,
      "sha256" => Digest::SHA256.file(path).hexdigest,
      "byte_size" => path.size
    }
  end

  def write_output(manifest, batch, imported)
    FileUtils.mkdir_p(@output_path.dirname)
    @output_path.write(JSON.pretty_generate(manifest) << "\n")
    summary = {
      "institutions_searched" => batch.fetch("institution_count"),
      "institutions_with_reports" => batch.fetch("institutions_with_reports"),
      "validated_report_assets" => batch.fetch("validated_report_count"),
      "imported_document_works" => imported,
      "output" => @output_path.to_s,
      "sha256" => Digest::SHA256.file(@output_path).hexdigest
    }
    puts JSON.pretty_generate(summary)
  end
end

if $PROGRAM_NAME == __FILE__
  options = {}
  OptionParser.new do |parser|
    parser.banner = "Usage: merge_municipal_financial_report_batch.rb --manifest PATH --batch PATH --output PATH"
    parser.on("--manifest PATH") { |value| options[:manifest_path] = value }
    parser.on("--batch PATH") { |value| options[:batch_path] = value }
    parser.on("--output PATH") { |value| options[:output_path] = value }
  end.parse!

  missing = %i[manifest_path batch_path output_path].reject { |key| options[key] }
  abort "missing options: #{missing.join(', ')}" if missing.any?

  MergeMunicipalFinancialReportBatch.new(**options).run
end
