#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "optparse"
require "pathname"
require "time"

class RecoverFirstNationFnftaAssets
  def initialize(manifest_path:, inventory_path:, legacy_root:, asset_root:, output_path:, audit_path:, recovered_at:)
    @manifest_path = Pathname(manifest_path).expand_path
    @inventory_path = Pathname(inventory_path).expand_path
    @legacy_root = Pathname(legacy_root).expand_path
    @asset_root = Pathname(asset_root).expand_path
    @output_path = Pathname(output_path).expand_path
    @audit_path = Pathname(audit_path).expand_path
    @recovered_at = Time.iso8601(recovered_at).utc.iso8601
  end

  def run
    [ @output_path, @audit_path ].each { |path| raise "refusing to overwrite #{path}" if path.exist? }
    manifest = JSON.parse(@manifest_path.read)
    inventory = JSON.parse(@inventory_path.read)
    release_version = manifest.fetch("release_version")
    raise "inventory release mismatch" unless inventory.fetch("release_version") == release_version

    band_numbers = manifest.fetch("bands").to_h do |band|
      [ band.fetch("canonical_id"), band.fetch("band_number").to_s ]
    end
    failures = inventory.fetch("assets").select { _1["error"] }
    recovered = []
    rejected = []
    failures.each do |attempt|
      asset, rejection = recover(attempt, band_numbers)
      asset ? recovered << asset : rejected << rejection
    end

    write_json(@output_path, {
      "release_version" => release_version,
      "generated_at" => @recovered_at,
      "manifest_path" => @manifest_path.to_s,
      "source_inventory_path" => @inventory_path.to_s,
      "legacy_root" => @legacy_root.to_s,
      "assets" => recovered
    })
    write_json(@audit_path, {
      "release_version" => release_version,
      "audited_at" => @recovered_at,
      "failed_input_count" => failures.length,
      "recovered_asset_count" => recovered.length,
      "remaining_failure_count" => rejected.length,
      "recovered_bytes" => recovered.sum { Integer(_1.fetch("byte_size")) },
      "rejection_reasons" => rejected.map { _1.fetch("reason") }.tally.sort.to_h,
      "rejections" => rejected,
      "output_inventory_path" => @output_path.to_s,
      "output_inventory_sha256" => Digest::SHA256.file(@output_path).hexdigest
    })
    puts JSON.pretty_generate(JSON.parse(@audit_path.read).except("rejections"))
  end

  private

  def recover(attempt, band_numbers)
    document_id = attempt.fetch("document_canonical_id")
    institution_id = document_id.split("/documents/", 2).first
    band_number = band_numbers[institution_id]
    year = document_id[%r{/financial-statements/(\d{4})/}, 1]
    return [ nil, rejection(document_id, "unmapped_document_id") ] unless band_number && year

    directory = @legacy_root.join("ISC_#{band_number}", year)
    files = directory.join("source").glob("financial_statement.*")
    return [ nil, rejection(document_id, "legacy_file_missing", band_number, year) ] if files.empty?
    return [ nil, rejection(document_id, "multiple_legacy_files", band_number, year) ] unless files.one?

    source = files.first
    metadata_path = directory.join("metadata.json")
    return [ nil, rejection(document_id, "legacy_metadata_missing", band_number, year) ] unless metadata_path.file?

    metadata = JSON.parse(metadata_path.read)
    statement = metadata.dig("source_files", "financial_statement") || {}
    return [ nil, rejection(document_id, "legacy_metadata_marks_corrupt", band_number, year) ] if statement["is_corrupted"]
    return [ nil, rejection(document_id, "legacy_metadata_has_error", band_number, year) ] if statement["error_message"]
    if statement["file_size_bytes"] && Integer(statement["file_size_bytes"]) != source.size
      return [ nil, rejection(document_id, "legacy_size_mismatch", band_number, year) ]
    end
    return [ nil, rejection(document_id, "invalid_pdf_magic", band_number, year) ] unless source.binread(5) == "%PDF-"

    digest = Digest::SHA256.file(source).hexdigest
    relative = Pathname("sha256").join(digest[0, 2], "#{digest}.pdf")
    archive(source, @asset_root.join(relative), digest)
    [ attempt.reject { |key, _value| key == "error" }.merge(
      "content_sha256" => digest,
      "asset_role" => "final",
      "preferred" => true,
      "retrieved_at" => @recovered_at,
      "archive_path" => relative.to_s,
      "mime_type" => "application/pdf",
      "byte_size" => source.size,
      "rights_status" => "metadata_only",
      "recovery_provenance" => {
        "method" => "legacy_fnfta_corpus_recovery",
        "legacy_path" => source.to_s,
        "legacy_metadata_path" => metadata_path.to_s,
        "legacy_original_path" => statement["original_path"],
        "legacy_created_at" => metadata["created_at"],
        "band_number" => band_number,
        "fiscal_year_end" => Integer(year)
      }.compact
    ), nil ]
  rescue JSON::ParserError, KeyError, ArgumentError => error
    [ nil, rejection(document_id, "invalid_legacy_metadata", band_number, year, error.message) ]
  end

  def archive(source, destination, digest)
    destination.dirname.mkpath
    if destination.exist?
      raise "content-address collision at #{destination}" unless Digest::SHA256.file(destination).hexdigest == digest
      return
    end

    temporary = destination.sub_ext(".pdf.tmp-#{Process.pid}")
    FileUtils.cp(source, temporary)
    raise "temporary archive hash mismatch" unless Digest::SHA256.file(temporary).hexdigest == digest

    FileUtils.mv(temporary, destination)
  end

  def rejection(document_id, reason, band_number = nil, year = nil, detail = nil)
    {
      "document_canonical_id" => document_id,
      "band_number" => band_number,
      "fiscal_year_end" => year&.to_i,
      "reason" => reason,
      "detail" => detail
    }.compact
  end

  def write_json(path, payload)
    path.dirname.mkpath
    path.write(JSON.pretty_generate(payload) << "\n")
  end
end

if $PROGRAM_NAME == __FILE__
  options = { recovered_at: Time.now.utc.iso8601 }
  OptionParser.new do |parser|
    parser.on("--manifest PATH") { |value| options[:manifest_path] = value }
    parser.on("--inventory PATH") { |value| options[:inventory_path] = value }
    parser.on("--legacy-root PATH") { |value| options[:legacy_root] = value }
    parser.on("--asset-root PATH") { |value| options[:asset_root] = value }
    parser.on("--output PATH") { |value| options[:output_path] = value }
    parser.on("--audit-output PATH") { |value| options[:audit_path] = value }
    parser.on("--recovered-at TIME") { |value| options[:recovered_at] = value }
  end.parse!
  required = %i[manifest_path inventory_path legacy_root asset_root output_path audit_path]
  missing = required.reject { options[_1] }
  abort "missing options: #{missing.join(', ')}" if missing.any?

  RecoverFirstNationFnftaAssets.new(**options).run
end
