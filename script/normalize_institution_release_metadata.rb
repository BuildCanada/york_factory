#!/usr/bin/env ruby
# frozen_string_literal: true

require "date"
require "json"
require "optparse"
require "pathname"
require "tempfile"
require "time"

options = { schema_version: "1.0" }
OptionParser.new do |parser|
  parser.banner = "Usage: normalize_institution_release_metadata.rb --published-at TIME MANIFEST..."
  parser.on("--published-at TIME", "Common ISO-8601 publication time") { options[:published_at] = Time.iso8601(_1).utc.iso8601 }
  parser.on("--schema-version VERSION", "Common schema version (default 1.0)") { options[:schema_version] = _1 }
end.parse!
abort("--published-at is required") unless options[:published_at]
abort("at least one manifest is required") if ARGV.empty?

ARGV.each do |filename|
  path = Pathname(filename)
  payload = JSON.parse(path.read)
  version = Date.iso8601(payload.fetch("release_version")).iso8601
  abort("#{path}: effective_on must match release_version") unless payload.fetch("effective_on") == version

  payload["schema_version"] = options.fetch(:schema_version)
  payload["published_at"] = options.fetch(:published_at)
  temporary = Tempfile.new([ path.basename.to_s, ".tmp" ], path.dirname)
  temporary.write(JSON.pretty_generate(payload) << "\n")
  temporary.close
  File.rename(temporary.path, path)
  puts "Normalized release metadata in #{path}"
ensure
  temporary&.close!
end
