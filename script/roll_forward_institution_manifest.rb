#!/usr/bin/env ruby

require "date"
require "json"
require "optparse"
require "pathname"
require "time"

options = {}
OptionParser.new do |parser|
  parser.banner = "usage: #{$PROGRAM_NAME} --input PATH --output PATH --version YYYY-MM-DD"
  parser.on("--input PATH") { |value| options[:input] = Pathname(value) }
  parser.on("--output PATH") { |value| options[:output] = Pathname(value) }
  parser.on("--version DATE") { |value| options[:version] = Date.iso8601(value) }
  parser.on("--published-at TIME") { |value| options[:published_at] = Time.iso8601(value).utc }
  parser.on("--schema-version VERSION") { |value| options[:schema_version] = value }
end.parse!

abort("--input, --output, and --version are required") unless options.values_at(:input, :output, :version).all?
abort("input manifest does not exist") unless options.fetch(:input).file?
abort("refusing to overwrite #{options.fetch(:output)}") if options.fetch(:output).exist?

payload = JSON.parse(options.fetch(:input).read)
version = options.fetch(:version).iso8601
published_at = options.fetch(:published_at, Time.iso8601("#{version}T00:00:00Z"))
province_code = payload.fetch("province").fetch("statcan_code")
payload["release_version"] = version
payload["effective_on"] = version
payload["published_at"] = published_at.iso8601
payload["schema_version"] = options.fetch(:schema_version, payload.fetch("schema_version"))
payload["derived_from_release_manifest"] = options.fetch(:input).to_s
payload.fetch("municipalities").each do |row|
  row["identifiers"] = Array(row["identifiers"]).reject do |identifier|
    identifier.fetch("scheme").start_with?("statcan.")
  end
  Array(row["statcan_geographies"]).each do |geography|
    geography["boundary_type"] ||= "csd"
    geography["role"] ||= "governs"
    geography["province_code"] ||= province_code
  end
end
payload["relationships"] ||= []

output = options.fetch(:output)
output.dirname.mkpath
output.write(JSON.pretty_generate(payload) << "\n")

puts JSON.pretty_generate(
  "release_version" => version,
  "institutions" => payload.fetch("municipalities").length,
  "documents" => payload.fetch("municipalities").sum { |row| Array(row["documents"]).length },
  "relationships" => payload.fetch("relationships").length,
  "statcan_organization_identifiers" => payload.fetch("municipalities").sum do |row|
    Array(row["identifiers"]).count { |identifier| identifier.fetch("scheme").start_with?("statcan.") }
  end
)
