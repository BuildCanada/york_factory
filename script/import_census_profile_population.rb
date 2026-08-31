#!/usr/bin/env ruby

require_relative "../config/environment"
require "optparse"

options = { retrieved_at: Time.current }
OptionParser.new do |parser|
  parser.banner = "Usage: bin/rails runner script/import_census_profile_population.rb --zip PATH --sha256 SHA --retrieved-at ISO8601"
  parser.on("--zip PATH") { |value| options[:zip_path] = value }
  parser.on("--sha256 SHA") { |value| options[:expected_sha256] = value }
  parser.on("--retrieved-at ISO8601") { |value| options[:retrieved_at] = Time.iso8601(value) }
end.parse!
missing = %i[zip_path expected_sha256].reject { |key| options[key].present? }
abort "missing options: #{missing.join(', ')}" if missing.any?

result = Warehouse::CensusProfileImporter.new(**options).import!
puts JSON.pretty_generate(result)
