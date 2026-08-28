#!/usr/bin/env ruby
# frozen_string_literal: true

require "date"
require "digest"
require "json"
require "optparse"
require "pathname"
require "time"

options = { schema_version: "1.1" }
OptionParser.new do |parser|
  parser.banner = "Usage: roll_forward_municipal_manifest.rb --input PATH --output PATH --release-version DATE --published-at ISO8601"
  parser.on("--input PATH") { |value| options[:input] = Pathname(value).expand_path }
  parser.on("--output PATH") { |value| options[:output] = Pathname(value).expand_path }
  parser.on("--release-version DATE") { |value| options[:release_version] = Date.iso8601(value).iso8601 }
  parser.on("--published-at ISO8601") { |value| options[:published_at] = Time.iso8601(value).utc.iso8601 }
  parser.on("--schema-version VERSION") { |value| options[:schema_version] = value }
end.parse!

missing = %i[input output release_version published_at].reject { |key| options[key] }
abort "missing options: #{missing.join(', ')}" if missing.any?
abort "refusing to overwrite #{options.fetch(:output)}" if options.fetch(:output).exist?

payload = JSON.parse(options.fetch(:input).read)
payload["release_version"] = options.fetch(:release_version)
payload["effective_on"] = options.fetch(:release_version)
payload["published_at"] = options.fetch(:published_at)
payload["schema_version"] = options.fetch(:schema_version)
payload["derived_from_release_manifest"] = options.fetch(:input).to_s
options.fetch(:output).dirname.mkpath
options.fetch(:output).write(JSON.pretty_generate(payload) << "\n")

puts JSON.pretty_generate(
  "province" => payload.fetch("province").fetch("code"),
  "institutions" => payload.fetch("municipalities").length,
  "documents" => payload.fetch("municipalities").sum { |row| row.fetch("documents", []).length },
  "output" => options.fetch(:output).to_s,
  "sha256" => Digest::SHA256.file(options.fetch(:output)).hexdigest
)
