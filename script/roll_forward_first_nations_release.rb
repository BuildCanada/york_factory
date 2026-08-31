#!/usr/bin/env ruby
# frozen_string_literal: true

require "date"
require "fileutils"
require "json"
require "optparse"

options = {
  schema_version: "1.1"
}

OptionParser.new do |parser|
  parser.banner = "Usage: roll_forward_first_nations_release.rb --manifest PATH --assets PATH --output-dir PATH --release-version YYYY-MM-DD"
  parser.on("--manifest PATH") { |value| options[:manifest] = value }
  parser.on("--assets PATH") { |value| options[:assets] = value }
  parser.on("--output-dir PATH") { |value| options[:output_dir] = value }
  parser.on("--release-version VERSION") { |value| options[:release_version] = value }
  parser.on("--schema-version VERSION") { |value| options[:schema_version] = value }
end.parse!

required = %i[manifest assets output_dir release_version]
missing = required.reject { |key| options[key] }
abort "Missing options: #{missing.join(", ")}" if missing.any?

Date.iso8601(options.fetch(:release_version))

manifest = JSON.parse(File.read(options.fetch(:manifest)))
assets = JSON.parse(File.read(options.fetch(:assets)))

output_dir = File.expand_path(options.fetch(:output_dir))
manifest_path = File.join(output_dir, "normalized-manifest.json")
assets_path = File.join(output_dir, "financial-statement-assets-normalized.json")
[ manifest_path, assets_path ].each { |path| abort "Refusing to overwrite #{path}" if File.exist?(path) }

manifest["release_version"] = options.fetch(:release_version)
manifest["effective_on"] = options.fetch(:release_version)
manifest["schema_version"] = options.fetch(:schema_version)
manifest["derived_from_release_manifest"] = File.expand_path(options.fetch(:manifest))

assets["release_version"] = options.fetch(:release_version)
assets["manifest_path"] = manifest_path
assets["derived_from_asset_inventory"] = File.expand_path(options.fetch(:assets))

FileUtils.mkdir_p(output_dir)
File.write(manifest_path, JSON.pretty_generate(manifest) + "\n")
File.write(assets_path, JSON.pretty_generate(assets) + "\n")

puts JSON.generate(
  release_version: options.fetch(:release_version),
  schema_version: options.fetch(:schema_version),
  bands: manifest.fetch("bands").length,
  assets: assets.fetch("assets").length,
  manifest_path: manifest_path,
  assets_path: assets_path
)
