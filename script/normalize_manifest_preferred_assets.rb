#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "optparse"
require "pathname"

options = {}
OptionParser.new do |parser|
  parser.banner = "Usage: normalize_manifest_preferred_assets.rb --manifest PATH --output PATH"
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
normalized_documents = []

payload.fetch("municipalities").each do |institution|
  Array(institution["documents"]).each do |document|
    assets = Array(document["assets"])
    next if assets.empty? || assets.count { |asset| asset["preferred"] } == 1

    preferred_index = assets.index { |asset| asset["preferred"] } || 0
    assets.each_with_index { |asset, index| asset["preferred"] = index == preferred_index }
    normalized_documents << document.fetch("canonical_id")
  end
end

payload["preferred_asset_normalization"] = {
  "source_manifest_path" => manifest_path.to_s,
  "source_manifest_sha256" => Digest::SHA256.file(manifest_path).hexdigest,
  "normalized_document_count" => normalized_documents.length,
  "normalized_document_ids" => normalized_documents
}

output_path.write(JSON.pretty_generate(payload) << "\n")
puts JSON.pretty_generate(
  "output" => output_path.to_s,
  "output_sha256" => Digest::SHA256.file(output_path).hexdigest,
  "normalized_document_count" => normalized_documents.length
)
