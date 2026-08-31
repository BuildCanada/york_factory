#!/usr/bin/env ruby
# frozen_string_literal: true

require "date"
require "digest"
require "fileutils"
require "json"
require "optparse"
require "pathname"
require "time"

class ReassignManifestFinancialStatementYears
  MISMATCH_PATTERN = /\APDF fiscal year ((?:19|20)\d{2}) does not match document fiscal year ((?:19|20)\d{2})\z/
  DEFAULT_ASSET_ROOT = Pathname("/Volumes/floppy/york_factory/public_institutions/assets")

  def initialize(manifest_path:, audit_path:, output_path:, transformed_at:, asset_root: DEFAULT_ASSET_ROOT)
    @manifest_path = Pathname(manifest_path).expand_path
    @audit_path = Pathname(audit_path).expand_path
    @output_path = Pathname(output_path).expand_path
    @transformed_at = Time.iso8601(transformed_at).utc
    @asset_root = Pathname(asset_root).expand_path
  end

  def run
    raise "missing manifest #{@manifest_path}" unless @manifest_path.file?
    raise "missing audit #{@audit_path}" unless @audit_path.file?
    raise "refusing to overwrite #{@output_path}" if @output_path.exist?

    manifest = JSON.parse(@manifest_path.read)
    audit = JSON.parse(@audit_path.read)
    verify_audit_source!(audit)
    moves = mismatch_moves(audit)
    applied = apply_moves!(manifest, moves)
    verify_manifest!(manifest, applied)

    manifest["financial_statement_fiscal_year_reassignment"] = {
      "transformed_at" => @transformed_at.iso8601,
      "source_manifest_path" => @manifest_path.to_s,
      "source_manifest_sha256" => Digest::SHA256.file(@manifest_path).hexdigest,
      "source_audit_path" => @audit_path.to_s,
      "source_audit_sha256" => Digest::SHA256.file(@audit_path).hexdigest,
      "moved_asset_count" => applied.length,
      "moves" => applied
    }

    FileUtils.mkdir_p(@output_path.dirname)
    @output_path.write(JSON.pretty_generate(manifest) << "\n")
    result = {
      "output" => @output_path.to_s,
      "output_sha256" => Digest::SHA256.file(@output_path).hexdigest,
      "moved_asset_count" => applied.length,
      "source_document_count" => applied.map { |row| row.fetch("source_document_id") }.uniq.length,
      "target_document_count" => applied.map { |row| row.fetch("target_document_id") }.uniq.length
    }
    puts JSON.pretty_generate(result)
    result
  end

  private

  def verify_audit_source!(audit)
    expected_path = Pathname(audit.fetch("source_manifest_path")).expand_path
    raise "audit source path does not match manifest" unless expected_path == @manifest_path

    actual_sha = Digest::SHA256.file(@manifest_path).hexdigest
    raise "audit source SHA-256 does not match manifest" unless audit.fetch("source_manifest_sha256") == actual_sha
  end

  def mismatch_moves(audit)
    audit.fetch("rejected_assets").filter_map do |row|
      match = row.fetch("reason").match(MISMATCH_PATTERN)
      next unless match

      row.merge(
        "verified_fiscal_year" => Integer(match[1]),
        "manifest_fiscal_year" => Integer(match[2])
      )
    end
  end

  def apply_moves!(manifest, moves)
    institutions = manifest.fetch("municipalities").to_h { |row| [ row.fetch("canonical_id"), row ] }
    located = moves.map { |move| locate_move!(institutions, move) }

    # Remove every affected asset first. This makes reversed year sequences and
    # chains deterministic instead of depending on move order.
    located.each do |entry|
      assets = entry.fetch("source_document").fetch("assets")
      before = assets.length
      move = entry.fetch("move")
      assets.delete_if do |asset|
        asset["content_sha256"] == move.fetch("content_sha256") &&
          asset["archive_path"] == move.fetch("archive_path")
      end
      raise "audited asset removal was not unique" unless assets.length == before - 1
    end

    applied = located.map do |entry|
      apply_move!(entry.fetch("institution"), entry.fetch("source_document"), entry.fetch("asset"), entry.fetch("move"))
    end

    institutions.each_value do |institution|
      documents = institution.fetch("documents", [])
      deduplicate_same_year_assets!(documents)
      documents.reject! { |document| document["document_type"] == "financial-statements" && Array(document["assets"]).empty? }
      documents.select { |document| document["document_type"] == "financial-statements" }.each do |document|
        normalize_assets!(document.fetch("assets"))
      end
      documents.sort_by! { |document| document.fetch("canonical_id") }
    end
    applied
  end

  def deduplicate_same_year_assets!(documents)
    seen = {}
    documents.select { |document| document["document_type"] == "financial-statements" }.each do |document|
      year = document_year(document)
      document.fetch("assets").delete_if do |asset|
        key = [ year, asset.fetch("content_sha256") ]
        duplicate = seen.key?(key)
        seen[key] ||= document.fetch("canonical_id")
        duplicate
      end
    end
  end

  def locate_move!(institutions, move)
    institution = institutions.fetch(move.fetch("institution_id"))
    source_document = institution.fetch("documents").find do |document|
      document.fetch("canonical_id") == move.fetch("document_id")
    end
    raise "missing source document #{move.fetch('document_id')}" unless source_document
    raise "source document is not financial-statements" unless source_document["document_type"] == "financial-statements"

    expected_year = document_year(source_document)
    unless expected_year == move.fetch("manifest_fiscal_year")
      raise "source document year #{expected_year.inspect} does not match audit mismatch year #{move.fetch('manifest_fiscal_year')}"
    end

    asset_index = source_document.fetch("assets").index do |asset|
      asset["content_sha256"] == move.fetch("content_sha256") && asset["archive_path"] == move.fetch("archive_path")
    end
    raise "missing audited asset #{move.fetch('content_sha256')}" unless asset_index

    asset = source_document.fetch("assets").fetch(asset_index)
    verify_asset!(asset)
    {
      "move" => move,
      "institution" => institution,
      "source_document" => source_document,
      "asset" => asset
    }
  end

  def apply_move!(institution, source_document, asset, move)
    target_year = move.fetch("verified_fiscal_year")
    target_id = corrected_document_id(source_document.fetch("canonical_id"), target_year)
    documents = institution.fetch("documents")
    target_document = documents.find { |document| document.fetch("canonical_id") == target_id }
    operation = target_document ? "merged_into_existing_document" : "created_corrected_document"
    unless target_document
      target_document = corrected_document(institution, source_document, target_id, target_year)
      documents << target_document
    end
    target_document.fetch("assets") << asset unless target_document.fetch("assets").any? do |existing|
      existing["content_sha256"] == asset.fetch("content_sha256")
    end

    {
      "institution_id" => institution.fetch("canonical_id"),
      "content_sha256" => asset.fetch("content_sha256"),
      "source_document_id" => source_document.fetch("canonical_id"),
      "target_document_id" => target_id,
      "manifest_fiscal_year" => move.fetch("manifest_fiscal_year"),
      "verified_fiscal_year" => target_year,
      "operation" => operation,
      "evidence" => move.fetch("reason")
    }
  end

  def corrected_document(institution, source, target_id, year)
    source_year = document_year(source)
    source.merge(
      "canonical_id" => target_id,
      "title" => corrected_title(institution, source, source_year, year),
      "fiscal_period_start" => corrected_fiscal_date(source["fiscal_period_start"], source_year, year),
      "fiscal_period_end" => corrected_fiscal_date(source["fiscal_period_end"], source_year, year),
      "assets" => []
    )
  end

  def corrected_title(institution, source, source_year, target_year)
    title = source["title"] || source["title_en"] || source["title_fr"]
    return title.gsub(/\b#{source_year}\b/, target_year.to_s) if title&.match?(/\b#{source_year}\b/)
    return title if title

    "#{official_name(institution)} Financial Statements — #{target_year}"
  end

  def corrected_fiscal_date(value, source_year, target_year)
    return unless value

    date = Date.iso8601(value)
    Date.new(target_year + date.year - source_year, date.month, date.day).iso8601
  rescue Date::Error
    value
  end

  def corrected_document_id(document_id, year)
    corrected = document_id.sub(%r{/financial-statements/(?:19|20)\d{2}(?=/|\z)}, "/financial-statements/#{year}")
    raise "document ID has no replaceable fiscal year: #{document_id}" if corrected == document_id

    corrected
  end

  def document_year(document)
    return Date.iso8601(document.fetch("fiscal_period_end")).year if document["fiscal_period_end"]

    document.fetch("canonical_id")[%r{/financial-statements/((?:19|20)\d{2})(?:/|\z)}, 1]&.to_i
  rescue Date::Error
    nil
  end

  def verify_asset!(asset)
    expected_sha = asset.fetch("content_sha256")
    path = @asset_root.join(asset.fetch("archive_path"))
    raise "missing asset #{path}" unless path.file?
    raise "asset is not a PDF: #{path}" unless path.binread(5) == "%PDF-"
    raise "asset SHA-256 mismatch: #{path}" unless Digest::SHA256.file(path).hexdigest == expected_sha
  end

  def normalize_assets!(assets)
    assets.uniq! { |asset| asset.fetch("content_sha256") }
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

  def verify_manifest!(manifest, applied)
    raise "strict audit contained no fiscal-year mismatches" if applied.empty?

    seen_assets = {}
    manifest.fetch("municipalities").each do |institution|
      financial_documents = institution.fetch("documents", []).select do |document|
        document["document_type"] == "financial-statements"
      end
      ids = financial_documents.map { |document| document.fetch("canonical_id") }
      duplicates = ids.tally.select { |_id, count| count > 1 }.keys
      raise "duplicate financial-statement document IDs: #{duplicates.join(', ')}" if duplicates.any?

      financial_documents.each do |document|
        raise "financial-statement document has no assets: #{document.fetch('canonical_id')}" if document.fetch("assets").empty?
        raise "document canonical ID and fiscal period disagree: #{document.fetch('canonical_id')}" unless
          document.fetch("canonical_id").include?("/financial-statements/#{document_year(document)}/")

        document.fetch("assets").each do |asset|
          key = [ institution.fetch("canonical_id"), asset.fetch("content_sha256") ]
          raise "financial-statement asset appears in multiple fiscal years: #{key.join(' ')}" if seen_assets[key]

          seen_assets[key] = document.fetch("canonical_id")
        end
      end
    end
  end

  def official_name(institution)
    institution["official_name_en"] || institution["official_name_fr"] || institution.fetch("official_name")
  end
end

if $PROGRAM_NAME == __FILE__
  options = { asset_root: ReassignManifestFinancialStatementYears::DEFAULT_ASSET_ROOT }
  OptionParser.new do |parser|
    parser.banner = "Usage: reassign_manifest_financial_statement_years.rb --manifest PATH --audit PATH --output PATH --transformed-at ISO8601"
    parser.on("--manifest PATH") { |value| options[:manifest_path] = value }
    parser.on("--audit PATH") { |value| options[:audit_path] = value }
    parser.on("--output PATH") { |value| options[:output_path] = value }
    parser.on("--transformed-at TIME") { |value| options[:transformed_at] = value }
    parser.on("--asset-root PATH") { |value| options[:asset_root] = value }
  end.parse!

  missing = %i[manifest_path audit_path output_path transformed_at].reject { |key| options[key] }
  abort "missing options: #{missing.join(', ')}" if missing.any?

  ReassignManifestFinancialStatementYears.new(**options).run
end
