#!/usr/bin/env ruby
# frozen_string_literal: true

require "date"
require "digest"
require "json"
require "optparse"
require "pathname"

options = {}
OptionParser.new do |parser|
  parser.banner = "Usage: roll_forward_csd_authority_data.rb --input PATH --output PATH --release-version DATE"
  parser.on("--input PATH") { |value| options[:input] = Pathname(value).expand_path }
  parser.on("--output PATH") { |value| options[:output] = Pathname(value).expand_path }
  parser.on("--release-version DATE") { |value| options[:release_version] = Date.iso8601(value).iso8601 }
end.parse!

missing = %i[input output release_version].reject { |key| options[key] }
abort "missing options: #{missing.join(', ')}" if missing.any?
abort "refusing to overwrite #{options.fetch(:output)}" if options.fetch(:output).exist?

payload = JSON.parse(options.fetch(:input).read)
payload["release_version"] = options.fetch(:release_version)
payload["derived_from"] = {
  "path" => options.fetch(:input).to_s,
  "content_sha256" => Digest::SHA256.file(options.fetch(:input)).hexdigest
}
options.fetch(:output).dirname.mkpath
options.fetch(:output).write(JSON.pretty_generate(payload) << "\n")

puts JSON.generate(
  output: options.fetch(:output).to_s,
  mappings: Array(payload["mappings"]).length,
  csds: Array(payload["csds"]).length,
  sha256: Digest::SHA256.file(options.fetch(:output)).hexdigest
)
