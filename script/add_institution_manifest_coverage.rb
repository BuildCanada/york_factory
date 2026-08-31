#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "optparse"
require "pathname"
require "tempfile"

options = { roster_status: "complete", replace: false }
OptionParser.new do |parser|
  parser.banner = "Usage: add_institution_manifest_coverage.rb [options] MANIFEST..."
  parser.on("--roster-status STATUS", %w[complete partial], "Institution-roster coverage status") do |value|
    options[:roster_status] = value
  end
  parser.on("--replace", "Replace existing generated coverage rows") { options[:replace] = true }
end.parse!
abort("at least one manifest is required") if ARGV.empty?

ARGV.each do |filename|
  path = Pathname(filename)
  payload = JSON.parse(path.read)
  abort("#{path} already has coverage rows") if Array(payload["coverage"]).any? && !options[:replace]

  rows = payload.fetch("municipalities")
  scope = "ca/#{payload.fetch('province').fetch('code')}"
  source_url = payload.fetch("roster_source_url")
  relationships = Array(payload["relationships"])
  documents = rows.flat_map { |row| Array(row["documents"]) }
  assets = documents.flat_map { |document| Array(document["assets"]) }
  documents_with_assets = documents.count { |document| Array(document["assets"]).any? }
  website_count = rows.count { |row| row["website_url"].to_s.match?(/\Ahttps?:\/\//) }
  geography_count = rows.count { |row| Array(row["statcan_geographies"]).any? }

  coverage = [
    {
      "scope_id" => scope, "subject" => "institutions", "status" => options.fetch(:roster_status),
      "notes" => "#{rows.length} institutions frozen from the stated jurisdiction roster and documented supplements.",
      "source_url" => source_url
    },
    {
      "scope_id" => scope, "subject" => "websites",
      "status" => website_count == rows.length ? "complete" : "partial",
      "notes" => "Official website recorded for #{website_count} of #{rows.length} institutions.",
      "source_url" => source_url
    },
    {
      "scope_id" => scope, "subject" => "geographies",
      "status" => geography_count == rows.length ? "complete" : "partial",
      "notes" => "Frozen StatsCan 2021 geography associated with #{geography_count} of #{rows.length} institutions; absence is not an organization-identity failure.",
      "source_url" => payload.fetch("geography_source_url")
    },
    {
      "scope_id" => scope, "subject" => "relationships",
      "status" => relationships.any? ? "partial" : "not-searched",
      "notes" => "#{relationships.length} evidence-backed relationships included; the release does not claim exhaustive graph coverage.",
      "source_url" => source_url
    }
  ]

  %w[financial-statements annual-report statement-of-financial-information financial-data-return].each do |document_type|
    matching = documents.select { |document| document["document_type"] == document_type }
    institutions = matching.map { |document| document.fetch("canonical_id").split("/documents/").first }.uniq.length
    coverage << {
      "scope_id" => scope,
      "subject" => document_type == "annual-report" ? "annual-reports" : document_type,
      "status" => matching.any? ? "partial" : "not-searched",
      "notes" => "#{matching.length} #{document_type} works recorded for #{institutions} of #{rows.length} institutions; missing rows do not assert that no document exists.",
      "source_url" => source_url
    }
  end

  coverage << {
    "scope_id" => scope, "subject" => "document-assets",
    "status" => documents.any? && documents_with_assets == documents.length ? "complete" : (assets.any? ? "partial" : "not-searched"),
    "notes" => "#{assets.length} archived assets attached to #{documents_with_assets} of #{documents.length} document works; metadata-only works may have no bundled binary.",
    "source_url" => source_url
  }
  payload["coverage"] = coverage

  temporary = Tempfile.new([ path.basename.to_s, ".tmp" ], path.dirname)
  temporary.write(JSON.pretty_generate(payload) << "\n")
  temporary.close
  File.rename(temporary.path, path)
  puts "Added #{coverage.length} coverage rows to #{path}"
ensure
  temporary&.close!
end
