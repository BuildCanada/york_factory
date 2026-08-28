#!/usr/bin/env ruby

require "optparse"
require_relative "../config/environment"

options = {
  verify_assets: true
}
parser = OptionParser.new do |opts|
  opts.banner = "usage: #{$PROGRAM_NAME} --version YYYY-MM-DD [options] BASE_JSON OUTPUT_JSON BATCH_JSON..."
  opts.on("--version VERSION", "Dated release version (required)") { |value| options[:release_version] = value }
  opts.on("--effective-on DATE", "Effective date; defaults to version") { |value| options[:effective_on] = value }
  opts.on("--published-at TIME", "Frozen publication timestamp") { |value| options[:published_at] = value }
  opts.on("--source-retrieved-at TIME", "Frozen roster/website retrieval timestamp") do |value|
    options[:source_retrieved_at] = value
  end
  opts.on("--previous PATH", "Previous release manifest for canonical-ID checks") { |value| options[:previous_path] = value }
  opts.on("--asset-root PATH", "Content-addressed asset root") { |value| options[:asset_root] = value }
  opts.on("--skip-asset-verification", "Build metadata without mounting the asset store") do
    options[:verify_assets] = false
  end
end
parser.parse!

base_path, output_path, *batch_paths = ARGV
abort parser.to_s if options[:release_version].nil? || base_path.nil? || output_path.nil? || batch_paths.empty?

builder = Warehouse::InstitutionRelease::NovaScotiaMunicipalityManifestBuilder.new(
  base_path: base_path,
  output_path: output_path,
  batch_paths: batch_paths,
  **options
)
output = builder.call

puts JSON.pretty_generate(
  "release" => output.fetch("release_version"),
  "municipalities" => output.fetch("municipalities").length,
  "document_works" => output.fetch("municipalities").sum { |row| row.fetch("documents").length },
  "document_assets" => output.fetch("municipalities").sum do |row|
    row.fetch("documents").sum { |document| document.fetch("assets").length }
  end,
  "warnings" => builder.warnings
)
