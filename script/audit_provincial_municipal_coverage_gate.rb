#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "optparse"
require "pathname"
require "time"

class AuditProvincialMunicipalCoverageGate
  NAME_FIELDS = %w[official_name official_name_en official_name_fr].freeze

  def initialize(config_path:, output_path:, asset_root:)
    @config_path = Pathname(config_path).expand_path
    @output_path = Pathname(output_path).expand_path
    @asset_root = Pathname(asset_root).expand_path
    @valid_asset_cache = {}
  end

  def run
    raise "missing config #{@config_path}" unless @config_path.file?
    raise "refusing to overwrite #{@output_path}" if @output_path.exist?

    config = JSON.parse(@config_path.read)
    thresholds = config.fetch("thresholds")
    provinces = config.fetch("provinces").map { |province| audit_province(province, thresholds) }
    payload = {
      "generated_at" => config.fetch("generated_at"),
      "config_path" => @config_path.to_s,
      "config_sha256" => Digest::SHA256.file(@config_path).hexdigest,
      "definitions" => {
        "metadata_complete" => "canonical ID, upstream official name, and website or official directory profile URL",
        "financial_statement_downloaded" => "at least one financial-statements document with a local PDF whose size and SHA-256 match the manifest"
      },
      "thresholds" => thresholds,
      "all_provinces_pass" => provinces.all? { |province| province.fetch("passes") },
      "provinces" => provinces
    }
    @output_path.write(JSON.pretty_generate(payload) << "\n")
    puts JSON.pretty_generate(payload)
    raise "one or more provinces failed the coverage gate" unless payload.fetch("all_provinces_pass")
  end

  private

  def audit_province(config, thresholds)
    manifest_path = Pathname(config.fetch("manifest_path")).expand_path
    manifest = JSON.parse(manifest_path.read)
    rows = scoped_rows(manifest.fetch("municipalities"), config)
    metadata_rows = rows.select { |row| metadata_complete?(row) }
    statement_rows = rows.select { |row| downloaded_statement?(row) }
    metadata_required = required_count(rows.length, thresholds.fetch("metadata_percent"))
    statement_required = required_count(rows.length, thresholds.fetch("financial_statements_percent"))

    {
      "province" => config.fetch("province"),
      "manifest_path" => manifest_path.to_s,
      "manifest_sha256" => Digest::SHA256.file(manifest_path).hexdigest,
      "scope_note" => config.fetch("scope_note"),
      "institution_count" => rows.length,
      "metadata_complete_count" => metadata_rows.length,
      "metadata_required_count" => metadata_required,
      "metadata_percent" => percentage(metadata_rows.length, rows.length),
      "downloaded_financial_statement_count" => statement_rows.length,
      "downloaded_financial_statement_required_count" => statement_required,
      "downloaded_financial_statement_percent" => percentage(statement_rows.length, rows.length),
      "missing_metadata_ids" => rows.filter_map { |row| row["canonical_id"] unless metadata_complete?(row) },
      "missing_downloaded_financial_statement_ids" => rows.filter_map do |row|
        row["canonical_id"] unless downloaded_statement?(row)
      end,
      "passes" => metadata_rows.length >= metadata_required && statement_rows.length >= statement_required
    }
  end

  def scoped_rows(rows, config)
    included_types = Array(config["included_municipality_types"])
    excluded_types = Array(config["excluded_municipality_types"])
    rows.select do |row|
      type = row["municipality_type"]
      (included_types.empty? || included_types.include?(type)) && !excluded_types.include?(type)
    end
  end

  def metadata_complete?(row)
    row["canonical_id"].to_s != "" &&
      NAME_FIELDS.any? { |field| row[field].to_s != "" } &&
      row["website_url"].to_s != ""
  end

  def downloaded_statement?(row)
    Array(row["documents"]).any? do |document|
      document["document_type"] == "financial-statements" && Array(document["assets"]).any? do |asset|
        valid_asset?(asset)
      end
    end
  end

  def valid_asset?(asset)
    cache_key = [ asset["archive_path"], asset["byte_size"], asset["content_sha256"] ]
    return @valid_asset_cache.fetch(cache_key) if @valid_asset_cache.key?(cache_key)

    path = @asset_root.join(asset.fetch("archive_path"))
    @valid_asset_cache[cache_key] = path.file? && path.size == Integer(asset.fetch("byte_size")) &&
      path.binread(5) == "%PDF-" &&
      Digest::SHA256.file(path).hexdigest == asset.fetch("content_sha256")
  rescue KeyError, ArgumentError
    false
  end

  def required_count(total, percent)
    (total * Float(percent) / 100).ceil
  end

  def percentage(count, total)
    return 0.0 if total.zero?

    (count.fdiv(total) * 100).round(1)
  end
end

options = { asset_root: "/Volumes/floppy/york_factory/public_institutions/assets" }
OptionParser.new do |parser|
  parser.banner = "Usage: audit_provincial_municipal_coverage_gate.rb --config PATH --output PATH"
  parser.on("--config PATH") { |value| options[:config_path] = value }
  parser.on("--output PATH") { |value| options[:output_path] = value }
  parser.on("--asset-root PATH") { |value| options[:asset_root] = value }
end.parse!

missing = %i[config_path output_path].reject { |key| options[key] }
abort "missing options: #{missing.join(', ')}" if missing.any?

AuditProvincialMunicipalCoverageGate.new(**options).run
