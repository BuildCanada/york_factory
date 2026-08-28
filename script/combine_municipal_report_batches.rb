#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "optparse"
require "pathname"

options = { inputs: [] }
OptionParser.new do |parser|
  parser.banner = "Usage: combine_municipal_report_batches.rb --output PATH --input PATH [--input PATH ...]"
  parser.on("--output PATH") { |value| options[:output] = Pathname(value).expand_path }
  parser.on("--input PATH") { |value| options[:inputs] << Pathname(value).expand_path }
  parser.on("--batch NAME", "Combined batch identifier") { |value| options[:batch] = value }
end.parse!

abort "missing --output" unless options[:output]
abort "at least one --input is required" if options[:inputs].empty?
abort "refusing to overwrite #{options[:output]}" if options[:output].exist?

batches = options[:inputs].map { |path| JSON.parse(path.read) }
source_manifests = batches.filter_map { |batch| batch["source_manifest"] }.uniq
abort "input batches reference different source manifests" if source_manifests.length > 1
institutions = batches.flat_map { |batch| batch.fetch("institutions") }
  .select { |institution| institution.fetch("reports").any? }
  .group_by { |institution| institution.fetch("canonical_id") }
  .map do |_canonical_id, versions|
    combined = versions.first.dup
    combined["searched_locations"] = versions.flat_map { |row| Array(row["searched_locations"]) }.uniq.sort
    combined["candidate_count"] = versions.sum { |row| Integer(row.fetch("candidate_count", 0)) }
    combined["reports"] = versions.flat_map { |row| row.fetch("reports") }.uniq do |report|
      [ report.fetch("document_type"), report.fetch("year"), report.fetch("content_sha256") ]
    end.sort_by { |report| [ report.fetch("document_type"), report.fetch("year"), report.fetch("download_url") ] }
    combined["validated_report_count"] = combined.fetch("reports").length
    combined["gaps"] = versions.flat_map { |row| Array(row["gaps"]) }.uniq
    combined["discovery_errors"] = versions.flat_map { |row| Array(row["discovery_errors"]) }.uniq
    combined["candidate_errors"] = versions.flat_map { |row| Array(row["candidate_errors"]) }.uniq
    combined
  end.sort_by { |institution| institution.fetch("canonical_id") }

reports = institutions.flat_map { |institution| institution.fetch("reports") }
payload = batches.first.merge(
  "batch" => options[:batch] || "combined-municipal-financial-reports-v1",
  "source_manifest" => source_manifests.first,
  "source_batch_names" => batches.filter_map { |batch| batch["batch"] }.uniq.sort,
  "source_batch_paths" => options[:inputs].map(&:to_s),
  "source_batch_sha256s" => options[:inputs].to_h { |path| [ path.to_s, Digest::SHA256.file(path).hexdigest ] },
  "institution_count" => institutions.length,
  "institutions_with_reports" => institutions.count { |institution| institution.fetch("reports").any? },
  "validated_report_count" => reports.length,
  "financial_statement_count" => reports.count { |report| report.fetch("document_type") == "financial-statements" },
  "annual_report_count" => reports.count { |report| report.fetch("document_type") == "annual-report" },
  "sofi_count" => reports.count { |report| report.fetch("document_type") == "statement-of-financial-information" },
  "institutions" => institutions
)

options[:output].dirname.mkpath
options[:output].write(JSON.pretty_generate(payload) << "\n")
puts JSON.pretty_generate(
  payload.slice(
    "institution_count",
    "institutions_with_reports",
    "validated_report_count",
    "financial_statement_count",
    "annual_report_count",
    "sofi_count"
  ).merge("output" => options[:output].to_s, "sha256" => Digest::SHA256.file(options[:output]).hexdigest)
)
