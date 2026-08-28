#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "optparse"
require "pathname"
require "time"

class MergeMunicipalManifestDocuments
  def initialize(manifest_path:, donor_path:, output_path:, merged_at:, document_type: "financial-statements")
    @manifest_path = Pathname(manifest_path).expand_path
    @donor_path = Pathname(donor_path).expand_path
    @output_path = Pathname(output_path).expand_path
    @merged_at = Time.iso8601(merged_at).utc
    @document_type = document_type
  end

  def run
    raise "refusing to overwrite #{@output_path}" if @output_path.exist?

    manifest = JSON.parse(@manifest_path.read)
    donor = JSON.parse(@donor_path.read)
    validate_compatible!(manifest, donor)
    rows = manifest.fetch("municipalities")
    rows_by_id = rows.to_h { [ _1.fetch("canonical_id"), _1 ] }
    imported_documents = 0
    imported_assets = 0

    donor.fetch("municipalities").each do |donor_row|
      row = rows_by_id.fetch(donor_row.fetch("canonical_id"))
      documents = Array(row["documents"])
      by_id = documents.to_h { [ _1.fetch("canonical_id"), _1 ] }
      Array(donor_row["documents"]).each do |donor_document|
        next unless donor_document["document_type"] == @document_type
        next if Array(donor_document["assets"]).empty?

        document = by_id[donor_document.fetch("canonical_id")]
        unless document
          document = JSON.parse(JSON.generate(donor_document))
          normalize_assets!(document)
          documents << document
          by_id[document.fetch("canonical_id")] = document
          imported_documents += 1
          imported_assets += Array(document["assets"]).length
          next
        end

        existing_hashes = Array(document["assets"]).filter_map { _1["content_sha256"] }.to_h { [ _1, true ] }
        new_assets = Array(donor_document["assets"]).reject { existing_hashes[_1["content_sha256"]] }
        document["assets"] = Array(document["assets"]) + JSON.parse(JSON.generate(new_assets))
        normalize_assets!(document)
        imported_assets += new_assets.length
      end
      documents.each { normalize_assets!(_1) if Array(_1["assets"]).any? }
      row["documents"] = documents.sort_by { _1.fetch("canonical_id") }
    end

    update_coverage!(manifest, rows)
    manifest["merged_document_manifests"] ||= []
    manifest["merged_document_manifests"] << {
      "path" => @donor_path.to_s,
      "sha256" => Digest::SHA256.file(@donor_path).hexdigest,
      "merged_at" => @merged_at.iso8601,
      "document_type" => @document_type,
      "imported_documents" => imported_documents,
      "imported_assets" => imported_assets
    }
    FileUtils.mkdir_p(@output_path.dirname)
    @output_path.write(JSON.pretty_generate(manifest) << "\n")
    summary = {
      "institutions_with_documents" => institutions_with_documents(rows),
      "imported_documents" => imported_documents,
      "imported_assets" => imported_assets,
      "output" => @output_path.to_s,
      "sha256" => Digest::SHA256.file(@output_path).hexdigest
    }
    puts JSON.pretty_generate(summary)
    summary
  end

  private

  def validate_compatible!(manifest, donor)
    %w[release_version].each do |field|
      raise "#{field} mismatch" unless manifest[field] == donor[field]
    end
    base_code = manifest.dig("province", "code")
    donor_code = donor.dig("province", "code")
    raise "province mismatch" unless base_code == donor_code

    base_ids = manifest.fetch("municipalities").map { _1.fetch("canonical_id") }.sort
    donor_ids = donor.fetch("municipalities").map { _1.fetch("canonical_id") }.sort
    raise "municipal roster mismatch" unless base_ids == donor_ids
  end

  def update_coverage!(manifest, rows)
    count = institutions_with_documents(rows)
    assets = rows.sum do |row|
      Array(row["documents"]).select { _1["document_type"] == @document_type }
        .sum { Array(_1["assets"]).length }
    end
    coverage = manifest.fetch("coverage")
    record = coverage.find { _1["subject"] == @document_type }
    return unless record

    record["status"] = count == rows.length ? "complete" : "partial"
    record["notes"] = "#{count} of #{rows.length} institutions have #{assets} locally archived " \
      "#{@document_type} assets after merging a content-audited donor manifest."
  end

  def normalize_assets!(document)
    assets = Array(document["assets"])
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

  def institutions_with_documents(rows)
    rows.count do |row|
      Array(row["documents"]).any? do |document|
        document["document_type"] == @document_type && Array(document["assets"]).any?
      end
    end
  end
end

if $PROGRAM_NAME == __FILE__
  options = { document_type: "financial-statements" }
  OptionParser.new do |parser|
    parser.banner = "Usage: merge_municipal_manifest_documents.rb --manifest PATH --donor PATH --output PATH --merged-at ISO8601"
    parser.on("--manifest PATH") { options[:manifest_path] = _1 }
    parser.on("--donor PATH") { options[:donor_path] = _1 }
    parser.on("--output PATH") { options[:output_path] = _1 }
    parser.on("--merged-at TIME") { options[:merged_at] = _1 }
    parser.on("--document-type TYPE") { options[:document_type] = _1 }
  end.parse!

  missing = %i[manifest_path donor_path output_path merged_at].reject { options[_1] }
  abort "missing options: #{missing.join(', ')}" if missing.any?

  MergeMunicipalManifestDocuments.new(**options).run
end
