#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "date"
require "json"
require "optparse"
require "pathname"
require "set"
require "uri"

class ValidatePublicInstitutionManifest
  CANONICAL_ID = /\Aca\/[a-z0-9]+(?:-[a-z0-9]+)*(?:\/[a-z0-9]+(?:-[a-z0-9]+)*)*\z/
  DOCUMENT_TYPES = %w[
    annual-report auditor-report financial-data-return financial-statements other
    remuneration-report statement-of-financial-information
  ].freeze
  COVERAGE_STATUSES = %w[complete partial not-searched unavailable].freeze
  RELATIONSHIP_TYPES = %w[
    administrative_parent reports_to owned_by controlled_by consolidated_into
    governed_by operated_by member_of succeeds
  ].freeze
  OWNERSHIP_BASES = %w[equity voting statutory board_appointment accounting_control other].freeze

  def initialize(manifest_path:, output_path:, asset_root:)
    @manifest_path = Pathname(manifest_path).expand_path
    @output_path = Pathname(output_path).expand_path
    @asset_root = Pathname(asset_root).expand_path
    @errors = []
    @warnings = []
  end

  def run
    raise "refusing to overwrite #{@output_path}" if @output_path.exist?

    payload = JSON.parse(@manifest_path.read)
    validate_release(payload)
    validate_institutions(payload.fetch("municipalities"))
    validate_cross_institution_duplicate_assets(payload.fetch("municipalities"))
    validate_relationships(payload)
    validate_coverage(payload.fetch("coverage"))
    audit = audit_payload(payload)
    @output_path.write(JSON.pretty_generate(audit) << "\n")
    puts JSON.pretty_generate(audit)
    raise "manifest validation failed with #{@errors.length} errors" if @errors.any?
  end

  private

  def validate_release(payload)
    required = %w[release_version effective_on schema_version published_at geography_vintage attribution province municipalities coverage]
    required.each { |key| error("missing release field #{key}") unless payload.key?(key) }
    error("release_version and effective_on differ") unless payload["release_version"] == payload["effective_on"]
  end

  def validate_institutions(rows)
    duplicate_values(rows.map { |row| row["canonical_id"] }).each { |id| error("duplicate institution #{id}") }
    document_ids = []
    rows.each do |row|
      id = row["canonical_id"].to_s
      error("invalid institution canonical_id #{id}") unless id.match?(CANONICAL_ID)
      names = row.values_at("official_name_en", "official_name_fr", "official_name").compact
      error("institution #{id} has no upstream name") if names.all?(&:empty?)
      validate_url(row["website_url"], "institution #{id} website") if row["website_url"]
      Array(row["documents"]).each do |document|
        document_ids << document["canonical_id"]
        validate_document(row, document)
      end
    end
    duplicate_values(document_ids).each { |id| error("duplicate document #{id}") }
  end

  def validate_document(institution, document)
    id = document["canonical_id"].to_s
    institution_id = institution.fetch("canonical_id")
    error("invalid document canonical_id #{id}") unless id.match?(CANONICAL_ID)
    error("document #{id} is outside institution namespace") unless id.start_with?("#{institution_id}/documents/")
    error("unsupported document type for #{id}") unless DOCUMENT_TYPES.include?(document["document_type"])
    validate_url(document["source_page_url"], "document #{id} source_page_url") if document["source_page_url"]
    validate_url(document["download_url"], "document #{id} download_url") if document["download_url"]
    assets = Array(document["assets"])
    assets.each { |asset| validate_asset(id, asset) }
    preferred = assets.count { |asset| asset["preferred"] }
    error("document #{id} must have exactly one preferred asset") if assets.any? && preferred != 1
  end

  def validate_relationships(payload)
    institution_ids = payload.fetch("municipalities").map { _1.fetch("canonical_id") }.to_set
    jurisdiction_ids = declared_jurisdiction_ids(payload)
    relationships = Array(payload["relationships"])
    signatures = relationships.map do |relationship|
      [ relationship["source_id"], relationship["target_id"], relationship["relationship_type"], relationship["valid_from"] ]
    end
    duplicate_values(signatures).each { |signature| error("duplicate relationship #{signature.join(' ')}") }

    primary_sources = []
    relationships.each do |relationship|
      source_id = relationship["source_id"]
      target_id = relationship["target_id"]
      type = relationship["relationship_type"]
      error("relationship source is missing: #{source_id}") unless institution_ids.include?(source_id)
      unless institution_ids.include?(target_id) || jurisdiction_ids.include?(target_id)
        error("relationship target is missing: #{target_id}")
      end
      error("relationship source and target are identical: #{source_id}") if source_id == target_id
      error("unsupported relationship type #{type}") unless RELATIONSHIP_TYPES.include?(type)
      validate_url(relationship["source_url"], "relationship source_url") if relationship["source_url"]
      validate_relationship_dates(relationship)
      validate_relationship_ownership(relationship)
      next unless relationship["primary"]

      primary_sources << source_id
      error("primary relationship is not administrative_parent: #{source_id}") unless type == "administrative_parent"
    end
    duplicate_values(primary_sources).each { |id| error("institution has multiple primary parents: #{id}") }
    validate_primary_relationship_forest(relationships)
  end

  def validate_cross_institution_duplicate_assets(institutions)
    occurrences = institutions.flat_map do |institution|
      institution_id = institution["canonical_id"].to_s
      Array(institution["documents"]).flat_map do |document|
        document_id = document["canonical_id"].to_s
        Array(document["assets"]).filter_map do |asset|
          sha256 = asset["content_sha256"].to_s
          [ sha256, institution_id, document_id ] if sha256.match?(/\A[0-9a-f]{64}\z/)
        end
      end
    end

    occurrences.group_by(&:first).sort.each do |sha256, matches|
      institution_ids = matches.map { _1.fetch(1) }.uniq.sort
      next unless institution_ids.length > 1

      document_ids = matches.map { _1.fetch(2) }.uniq.sort
      warning(
        "duplicate asset content_sha256 #{sha256} across institutions " \
        "#{institution_ids.join(', ')}; documents #{document_ids.join(', ')}"
      )
    end
  end

  def declared_jurisdiction_ids(payload)
    return Set.new unless payload.fetch("include_jurisdiction_institution", true)

    province_code = payload.dig("province", "code").to_s.downcase
    return Set.new if province_code.empty? || !province_code.match?(/\A[a-z0-9]+(?:-[a-z0-9]+)*\z/)

    Set["ca/#{province_code}"]
  end

  def validate_relationship_dates(relationship)
    valid_from = Date.iso8601(relationship["valid_from"]) if relationship["valid_from"]
    valid_to = Date.iso8601(relationship["valid_to"]) if relationship["valid_to"]
    if valid_from && valid_to && valid_to < valid_from
      error("relationship valid_to precedes valid_from: #{relationship['source_id']} #{relationship['target_id']}")
    end
  rescue Date::Error
    error("invalid relationship validity date: #{relationship['source_id']} #{relationship['target_id']}")
  end

  def validate_relationship_ownership(relationship)
    percentage = Float(relationship["ownership_percentage"]) if relationship["ownership_percentage"]
    if percentage && !percentage.between?(0, 100)
      error("relationship ownership percentage is outside 0..100: #{relationship['source_id']} #{percentage}")
    end
    basis = relationship["ownership_basis"]
    error("unsupported relationship ownership basis #{basis}") if basis && !OWNERSHIP_BASES.include?(basis)
  rescue ArgumentError, TypeError
    error("invalid relationship ownership percentage: #{relationship['source_id']}")
  end

  def validate_primary_relationship_forest(relationships)
    parents = relationships.filter_map do |relationship|
      next unless relationship["primary"] && relationship["relationship_type"] == "administrative_parent"

      [ relationship.fetch("source_id"), relationship.fetch("target_id") ]
    end.to_h
    parents.each_key do |start|
      seen = Set.new
      current = start
      while current && parents[current]
        if seen.include?(current)
          error("primary administrative-parent cycle includes #{current}")
          break
        end
        seen << current
        current = parents[current]
      end
    end
  end

  def validate_asset(document_id, asset)
    hash = asset["content_sha256"].to_s
    error("invalid asset hash for #{document_id}") unless hash.match?(/\A[0-9a-f]{64}\z/)
    path = @asset_root.join(asset.fetch("archive_path"))
    unless path.file?
      error("missing asset #{path} for #{document_id}")
      return
    end
    error("asset byte size mismatch for #{document_id}: #{path}") unless path.size == Integer(asset.fetch("byte_size"))
    error("asset SHA-256 mismatch for #{document_id}: #{path}") unless Digest::SHA256.file(path).hexdigest == hash
    validate_url(asset["download_url"], "asset for #{document_id}")
  rescue KeyError, ArgumentError => exception
    error("invalid asset for #{document_id}: #{exception.message}")
  end

  def validate_coverage(rows)
    rows.each do |row|
      error("invalid coverage status #{row['status']}") unless COVERAGE_STATUSES.include?(row["status"])
      error("coverage row lacks notes for #{row['subject']}") if row["notes"].to_s.empty?
    end
  end

  def validate_url(value, field)
    uri = URI(value)
    error("invalid #{field}: #{value}") unless %w[http https].include?(uri.scheme) && uri.host
  rescue URI::InvalidURIError, TypeError
    error("invalid #{field}: #{value}")
  end

  def duplicate_values(values)
    values.tally.select { |_value, count| count > 1 }.keys
  end

  def audit_payload(payload)
    institutions = payload.fetch("municipalities")
    documents = institutions.flat_map { |row| Array(row["documents"]) }
    assets = documents.flat_map { |document| Array(document["assets"]) }
    {
      "manifest" => @manifest_path.to_s,
      "manifest_sha256" => Digest::SHA256.file(@manifest_path).hexdigest,
      "release_version" => payload.fetch("release_version"),
      "institution_count" => institutions.length,
      "institutions_with_websites" => institutions.count { |row| row["website_url"] },
      "institutions_with_documents" => institutions.count { |row| Array(row["documents"]).any? },
      "document_count" => documents.length,
      "asset_count" => assets.length,
      "relationship_count" => Array(payload["relationships"]).length,
      "document_types" => documents.map { |document| document.fetch("document_type") }.tally.sort.to_h,
      "error_count" => @errors.length,
      "errors" => @errors,
      "warning_count" => @warnings.length,
      "warnings" => @warnings
    }
  end

  def error(message)
    @errors << message
  end

  def warning(message)
    @warnings << message
  end
end

if $PROGRAM_NAME == __FILE__
  options = { asset_root: "/Volumes/floppy/york_factory/public_institutions/assets" }
  OptionParser.new do |parser|
    parser.banner = "Usage: validate_public_institution_manifest.rb --manifest PATH --output PATH [--asset-root PATH]"
    parser.on("--manifest PATH") { |value| options[:manifest_path] = value }
    parser.on("--output PATH") { |value| options[:output_path] = value }
    parser.on("--asset-root PATH") { |value| options[:asset_root] = value }
  end.parse!

  missing = %i[manifest_path output_path].reject { |key| options[key] }
  abort "missing options: #{missing.join(', ')}" if missing.any?

  ValidatePublicInstitutionManifest.new(**options).run
end
