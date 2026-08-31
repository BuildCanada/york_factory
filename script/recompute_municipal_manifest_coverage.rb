#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "optparse"
require "pathname"

options = {}
OptionParser.new do |parser|
  parser.banner = "Usage: recompute_municipal_manifest_coverage.rb --manifest PATH --output PATH"
  parser.on("--manifest PATH") { |value| options[:manifest_path] = Pathname(value).expand_path }
  parser.on("--output PATH") { |value| options[:output_path] = Pathname(value).expand_path }
end.parse!

missing = %i[manifest_path output_path].reject { |key| options[key] }
abort "missing options: #{missing.join(', ')}" if missing.any?

manifest_path = options.fetch(:manifest_path)
output_path = options.fetch(:output_path)
abort "missing manifest #{manifest_path}" unless manifest_path.file?
abort "refusing to overwrite #{output_path}" if output_path.exist?

payload = JSON.parse(manifest_path.read)
institutions = payload.fetch("municipalities")
documents = institutions.flat_map { |institution| Array(institution["documents"]) }
assets = documents.flat_map { |document| Array(document["assets"]) }
coverage = payload.fetch("coverage")

if (row = coverage.find { |item| item["subject"] == "document-assets" })
  row["status"] = assets.empty? ? "not-searched" : "partial"
  row["notes"] = "#{assets.length} SHA-256-addressed document assets are linked across the manifest."
end

payload["coverage_recomputation"] = {
  "source_manifest_path" => manifest_path.to_s,
  "source_manifest_sha256" => Digest::SHA256.file(manifest_path).hexdigest,
  "document_count" => documents.length,
  "asset_count" => assets.length
}

output_path.write(JSON.pretty_generate(payload) << "\n")
puts JSON.pretty_generate(
  "output" => output_path.to_s,
  "output_sha256" => Digest::SHA256.file(output_path).hexdigest,
  "document_count" => documents.length,
  "asset_count" => assets.length
)
