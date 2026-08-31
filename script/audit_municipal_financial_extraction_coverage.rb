#!/usr/bin/env ruby

require_relative "../config/environment"
require "fileutils"
require "optparse"

options = { release: "2026-08-27" }
OptionParser.new do |parser|
  parser.on("--release VERSION") { options[:release] = _1 }
  parser.on("--output PATH") { options[:output] = Pathname(_1).expand_path }
  parser.on("--provinces LIST") { options[:provinces] = _1.split(",").map(&:strip) }
end.parse!
abort "missing option: --output" unless options[:output]
abort "refusing to overwrite #{options[:output]}" if options[:output].exist?

release = Warehouse::InstitutionRelease.find_by!(version: options.fetch(:release))
payload = Warehouse::FinancialStatementExtraction::CoverageAudit.new(
  release:, provinces: options[:provinces]
).payload

FileUtils.mkdir_p(options[:output].dirname)
options[:output].write(JSON.pretty_generate(payload) << "\n")
puts JSON.pretty_generate(payload.except(:records).merge(output: options[:output].to_s))
