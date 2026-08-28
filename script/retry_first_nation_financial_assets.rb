#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../config/environment"
require "json"
require "optparse"
require "pathname"

options = { workers: 8, retrieved_at: Time.current.utc }
OptionParser.new do |parser|
  parser.on("--manifest PATH") { |value| options[:manifest_path] = Pathname(value) }
  parser.on("--inventory PATH") { |value| options[:inventory_path] = Pathname(value) }
  parser.on("--retry-output PATH") { |value| options[:retry_output] = Pathname(value) }
  parser.on("--merged-output PATH") { |value| options[:merged_output] = Pathname(value) }
  parser.on("--audit-output PATH") { |value| options[:audit_output] = Pathname(value) }
  parser.on("--workers N", Integer) { |value| options[:workers] = value }
  parser.on("--retrieved-at TIME") { |value| options[:retrieved_at] = Time.iso8601(value).utc }
end.parse!

required = %i[manifest_path inventory_path retry_output merged_output audit_output]
missing = required.reject { |key| options[key] }
abort "Missing options: #{missing.map { |key| "--#{key.to_s.tr('_', '-')}" }.join(', ')}" if missing.any?

manifest = JSON.parse(options.fetch(:manifest_path).read)
inventory = JSON.parse(options.fetch(:inventory_path).read)
retry_ids = inventory.fetch("assets").filter_map do |asset|
  asset.fetch("document_canonical_id") if asset["error"].present?
end.to_set
abort "No retryable failures found" if retry_ids.empty?

retry_manifest = manifest.slice("release_version")
retry_manifest["bands"] = manifest.fetch("bands").filter_map do |band|
  reports = band.fetch("reports").select { |report| retry_ids.include?(report.fetch("canonical_id")) }
  band.merge("reports" => reports) if reports.any?
end

temporary_manifest = options.fetch(:retry_output).sub_ext(".manifest.json")
temporary_manifest.dirname.mkpath
temporary_manifest.write("#{JSON.pretty_generate(retry_manifest)}\n")

Warehouse::InstitutionRelease::FirstNations::FinancialStatementArchiver.new(
  manifest_path: temporary_manifest,
  inventory_path: options.fetch(:retry_output),
  retrieved_at: options.fetch(:retrieved_at),
  workers: options.fetch(:workers)
).call

Warehouse::InstitutionRelease::FirstNations::AssetInventoryMerger.new(
  manifest_path: options.fetch(:manifest_path),
  inventory_paths: [ options.fetch(:inventory_path), options.fetch(:retry_output) ],
  output_path: options.fetch(:merged_output),
  audit_path: options.fetch(:audit_output)
).call

merged = JSON.parse(options.fetch(:merged_output).read).fetch("assets")
puts JSON.pretty_generate(
  retried: retry_ids.length,
  recovered: merged.count { |asset| retry_ids.include?(asset.fetch("document_canonical_id")) && asset["error"].blank? },
  successful_assets: merged.count { |asset| asset["error"].blank? },
  failed_assets: merged.count { |asset| asset["error"].present? },
  output: options.fetch(:merged_output).to_s
)
