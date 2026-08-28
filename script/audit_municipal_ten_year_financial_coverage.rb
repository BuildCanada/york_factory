#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "optparse"
require "pathname"
require "time"

class AuditMunicipalTenYearFinancialCoverage
  DEFAULT_ASSET_ROOT = Pathname("/Volumes/floppy/york_factory/public_institutions/assets")
  TARGET_YEAR_COUNT = 10
  YEAR_PATTERN = %r{/financial-statements/((?:19|20)\d{2})/}

  def initialize(config_path:, output_path:, asset_root: DEFAULT_ASSET_ROOT, allow_incomplete: false, ids_dir: nil,
    include_predecessors: false)
    @config_path = Pathname(config_path).expand_path
    @output_path = Pathname(output_path).expand_path
    @asset_root = Pathname(asset_root).expand_path
    @allow_incomplete = allow_incomplete
    @ids_dir = Pathname(ids_dir).expand_path if ids_dir
    @include_predecessors = include_predecessors
    @valid_asset_cache = {}
  end

  def run
    raise "missing config #{@config_path}" unless @config_path.file?
    raise "refusing to overwrite #{@output_path}" if @output_path.exist?

    config = JSON.parse(@config_path.read)
    provinces = config.fetch("provinces").map { |province| audit_province(province) }
    payload = build_payload(config, provinces)
    FileUtils.mkdir_p(@output_path.dirname)
    @output_path.write(JSON.pretty_generate(payload) << "\n")
    write_gap_id_files(payload) if @ids_dir
    puts JSON.pretty_generate(payload)
    raise "one or more municipalities have fewer than #{TARGET_YEAR_COUNT} downloaded years" if !@allow_incomplete && !payload.fetch("all_institutions_pass")

    payload
  end

  private

  def write_gap_id_files(payload)
    FileUtils.mkdir_p(@ids_dir)
    payload.fetch("provinces").each do |province|
      ids = province.fetch("gaps").map { _1.fetch("canonical_id") }.sort
      @ids_dir.join("#{province.fetch('province')}.txt").write(ids.join("\n") << (ids.empty? ? "" : "\n"))
    end
  end

  def build_payload(config, provinces)
    zero_statement_institutions = provinces.flat_map do |province|
      province.fetch("zero_statement_institutions").map do |institution|
        institution.merge("province" => province.fetch("province"))
      end
    end
    lineage_only_institutions = provinces.flat_map do |province|
      province.fetch("lineage_only_institutions").map do |institution|
        institution.merge("province" => province.fetch("province"))
      end
    end

    {
      "generated_at" => Time.now.utc.iso8601,
      "config_generated_at" => config.fetch("generated_at"),
      "config_path" => @config_path.to_s,
      "config_sha256" => Digest::SHA256.file(@config_path).hexdigest,
      "definition" => coverage_definition,
      "counting_basis" => @include_predecessors ? "issuer_and_sourced_predecessors" : "issuer_only",
      "target_distinct_year_count" => TARGET_YEAR_COUNT,
      "totals" => {
        "scoped_institution_count" => provinces.sum { _1.fetch("scoped_institution_count") },
        "eligible_institution_count" => provinces.sum { _1.fetch("eligible_institution_count") },
        "zero_statement_institution_count" => zero_statement_institutions.length,
        "zero_statement_institutions" => zero_statement_institutions,
        "lineage_only_institution_count" => lineage_only_institutions.length,
        "lineage_only_institutions" => lineage_only_institutions,
        "ten_year_complete_count" => provinces.sum { _1.fetch("ten_year_complete_count") },
        "lineage_assisted_complete_count" => provinces.sum { _1.fetch("lineage_assisted_complete_count") },
        "shortfall_institution_count" => provinces.sum { _1.fetch("shortfall_institution_count") },
        "missing_year_slot_count" => provinces.sum { _1.fetch("missing_year_slot_count") },
        "asset_integrity_error_count" => provinces.sum { _1.fetch("asset_integrity_error_count") }
      },
      "all_institutions_pass" => provinces.all? { _1.fetch("passes") },
      "provinces" => provinces
    }
  end

  def audit_province(config)
    manifest_path = Pathname(config.fetch("manifest_path")).expand_path
    manifest = JSON.parse(manifest_path.read)
    all_rows = manifest.fetch("municipalities")
    rows_by_id = all_rows.to_h { |row| [ row.fetch("canonical_id"), row ] }
    own_years_by_id = rows_by_id.transform_values { |row| downloaded_years(row) }
    predecessors_by_id = predecessor_graph(manifest)
    scoped = scoped_rows(all_rows, config)
    relevant_ids = scoped.map { _1.fetch("canonical_id") }
    if @include_predecessors
      relevant_ids.concat(scoped.flat_map { transitive_predecessors(_1.fetch("canonical_id"), predecessors_by_id) })
    end
    asset_integrity_errors = relevant_ids.uniq.sort.flat_map do |canonical_id|
      financial_statement_document_integrity_errors(rows_by_id.fetch(canonical_id))
    end
    institutions = scoped.filter_map do |row|
      own_years = own_years_by_id.fetch(row.fetch("canonical_id"))
      next if own_years.empty?

      predecessor_ids = @include_predecessors ? transitive_predecessors(row.fetch("canonical_id"), predecessors_by_id) : []
      years = (own_years + predecessor_ids.flat_map { |id| own_years_by_id.fetch(id, []) }).uniq.sort

      institution_summary(row).merge(
        "issuer_downloaded_years" => own_years,
        "issuer_downloaded_year_count" => own_years.length,
        "predecessor_ids" => predecessor_ids,
        "downloaded_years" => years,
        "downloaded_year_count" => years.length,
        "missing_year_count" => [ TARGET_YEAR_COUNT - years.length, 0 ].max,
        "passes" => years.length >= TARGET_YEAR_COUNT
      )
    end
    zero_statement_institutions = scoped.filter_map do |row|
      next if own_years_by_id.fetch(row.fetch("canonical_id")).any?

      predecessor_ids = @include_predecessors ? transitive_predecessors(row.fetch("canonical_id"), predecessors_by_id) : []
      predecessor_years = predecessor_ids.flat_map { |id| own_years_by_id.fetch(id, []) }.uniq.sort
      institution_summary(row).merge(
        "financial_statement_document_count" => financial_statement_document_count(row),
        "predecessor_ids" => predecessor_ids,
        "predecessor_downloaded_years" => predecessor_years,
        "predecessor_downloaded_year_count" => predecessor_years.length,
        "has_lineage_years" => predecessor_years.any?
      )
    end
    lineage_only_institutions = zero_statement_institutions.select { _1.fetch("has_lineage_years") }
    gaps = institutions.reject { _1.fetch("passes") }
    lineage_assisted = institutions.select do |institution|
      institution.fetch("passes") && institution.fetch("issuer_downloaded_year_count") < TARGET_YEAR_COUNT &&
        institution.fetch("predecessor_ids").any?
    end
    complete_count = institutions.length - gaps.length
    complete_percent = if institutions.empty? && asset_integrity_errors.any?
      0.0
    else
      percentage(complete_count, institutions.length)
    end

    {
      "province" => config.fetch("province"),
      "manifest_path" => manifest_path.to_s,
      "manifest_sha256" => Digest::SHA256.file(manifest_path).hexdigest,
      "scope_note" => config.fetch("scope_note"),
      "scoped_institution_count" => scoped.length,
      "eligible_institution_count" => institutions.length,
      "zero_statement_institution_count" => zero_statement_institutions.length,
      "zero_statement_institutions" => zero_statement_institutions,
      "lineage_only_institution_count" => lineage_only_institutions.length,
      "lineage_only_institutions" => lineage_only_institutions,
      "ten_year_complete_count" => complete_count,
      "ten_year_complete_percent" => complete_percent,
      "lineage_assisted_complete_count" => lineage_assisted.length,
      "lineage_assisted_completions" => lineage_assisted,
      "shortfall_institution_count" => gaps.length,
      "missing_year_slot_count" => gaps.sum { _1.fetch("missing_year_count") },
      "asset_integrity_error_count" => asset_integrity_errors.length,
      "asset_integrity_errors" => asset_integrity_errors,
      "passes" => gaps.empty? && asset_integrity_errors.empty?,
      "gaps" => gaps
    }
  end

  def coverage_definition
    basis = if @include_predecessors
      "issued by that institution or a transitively linked predecessor"
    else
      "issued by that institution"
    end
    "Every scoped municipality with at least one valid downloaded financial statement must have at least " \
      "#{TARGET_YEAR_COUNT} distinct fiscal years #{basis}."
  end

  def predecessor_graph(manifest)
    Array(manifest["relationships"]).each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |relationship, graph|
      next unless relationship["relationship_type"] == "succeeds"
      next unless relationship["source_url"].to_s.match?(%r{\Ahttps?://})

      graph[relationship.fetch("source_id")] << relationship.fetch("target_id")
    end
  end

  def transitive_predecessors(canonical_id, graph)
    found = []
    pending = Array(graph[canonical_id]).sort.reverse
    until pending.empty?
      predecessor_id = pending.pop
      next if predecessor_id == canonical_id || found.include?(predecessor_id)

      found << predecessor_id
      pending.concat(Array(graph[predecessor_id]).sort.reverse)
    end
    found.sort
  end

  def scoped_rows(rows, config)
    included_types = Array(config["included_municipality_types"])
    excluded_types = Array(config["excluded_municipality_types"])
    included_statuses = Array(config["included_statuses"])
    rows.select do |row|
      type = row["municipality_type"]
      status = row["status"] || "active"
      (included_types.empty? || included_types.include?(type)) && !excluded_types.include?(type) &&
        (included_statuses.empty? || included_statuses.include?(status))
    end
  end

  def downloaded_years(row)
    Array(row["documents"]).filter_map do |document|
      next unless document["document_type"] == "financial-statements"
      next unless Array(document["assets"]).any? { valid_asset?(_1) }

      document_year(document)
    end.uniq.sort
  end

  def financial_statement_document_integrity_errors(row)
    Array(row["documents"]).flat_map do |document|
      next unless document["document_type"] == "financial-statements"

      errors = []
      canonical_year, fiscal_year = document_year_parts(document)
      if canonical_year && fiscal_year && canonical_year != fiscal_year
        errors << {
          "canonical_id" => row.fetch("canonical_id"),
          "document_id" => document.fetch("canonical_id"),
          "reason" => "canonical ID year disagrees with fiscal_period_end year",
          "canonical_id_year" => canonical_year,
          "fiscal_period_end_year" => fiscal_year
        }
      end
      unless Array(document["assets"]).any? { valid_asset?(_1) }
        errors << {
          "canonical_id" => row.fetch("canonical_id"),
          "document_id" => document.fetch("canonical_id"),
          "reason" => "no SHA-256-verified local asset"
        }
      end
      errors
    end.compact
  end

  def document_year(document)
    canonical_year, fiscal_year = document_year_parts(document)
    return if canonical_year && fiscal_year && canonical_year != fiscal_year

    canonical_year || fiscal_year
  end

  def document_year_parts(document)
    [
      document["canonical_id"].to_s[YEAR_PATTERN, 1]&.to_i,
      document["fiscal_period_end"].to_s[/\A((?:19|20)\d{2})/, 1]&.to_i
    ]
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

  def official_name(row)
    row["official_name"] || row["official_name_en"] || row["official_name_fr"]
  end

  def institution_summary(row)
    {
      "canonical_id" => row.fetch("canonical_id"),
      "official_name" => official_name(row),
      "website_url" => row["website_url"]
    }
  end

  def financial_statement_document_count(row)
    Array(row["documents"]).count { _1["document_type"] == "financial-statements" }
  end

  def percentage(count, total)
    return 100.0 if total.zero?

    (count.fdiv(total) * 100).round(1)
  end
end

if $PROGRAM_NAME == __FILE__
  options = { asset_root: AuditMunicipalTenYearFinancialCoverage::DEFAULT_ASSET_ROOT }
  OptionParser.new do |parser|
    parser.banner = "Usage: audit_municipal_ten_year_financial_coverage.rb --config PATH --output PATH"
    parser.on("--config PATH") { |value| options[:config_path] = value }
    parser.on("--output PATH") { |value| options[:output_path] = value }
    parser.on("--asset-root PATH") { |value| options[:asset_root] = Pathname(value) }
    parser.on("--ids-dir PATH", "Write one gap-ID file per province") { |value| options[:ids_dir] = Pathname(value) }
    parser.on("--include-predecessors", "Count years issued by sourced predecessor institutions") do
      options[:include_predecessors] = true
    end
    parser.on("--allow-incomplete") { options[:allow_incomplete] = true }
  end.parse!

  missing = %i[config_path output_path].reject { |key| options[key] }
  abort "missing options: #{missing.join(', ')}" if missing.any?

  AuditMunicipalTenYearFinancialCoverage.new(**options).run
end
