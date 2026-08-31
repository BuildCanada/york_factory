#!/usr/bin/env ruby

require_relative "../config/environment"
require "optparse"

options = {}
OptionParser.new do |parser|
  parser.on("--audit PATH") { options[:audit] = Pathname(_1).expand_path }
  parser.on("--apply") { options[:apply] = true }
end.parse!
abort "missing option: --audit" unless options[:audit]
abort "missing audit #{options[:audit]}" unless options[:audit].file?

rows = options[:audit].each_line.filter_map do |line|
  row = JSON.parse(line)
  row if row["extraction_id"] && row["status"].in?(%w[pass mismatch failed])
rescue JSON::ParserError
  nil
end

counts = Hash.new(0)
rows.each do |row|
  extraction = Warehouse::FinancialStatementExtraction.find(row.fetch("extraction_id"))
  from_parser = row.fetch("from_parser")
  to_parser = row.fetch("to_parser")
  unless extraction.llm_response_snapshot&.fetch("parser", nil) == from_parser
    raise "extraction #{extraction.id} parser changed after audit"
  end
  unless extraction.status == "approved"
    raise "extraction #{extraction.id} is no longer approved"
  end

  passed = row.fetch("status") == "pass"
  check = {
    id: "parser_upgrade_reparse",
    status: passed ? "pass" : "fail",
    detail: if passed
              "#{from_parser} values reproduced exactly by #{to_parser} without arithmetic fallback"
            else
              "#{to_parser} could not reproduce the prior arithmetic-fallback result; see saved upgrade audit"
            end
  }
  attributes = {
    check_results: Array(extraction.check_results).reject do |existing|
      existing.stringify_keys["id"] == check.fetch(:id)
    end + [ check ]
  }
  unless passed
    attributes[:status] = "rejected"
    attributes[:review_notes] = [ extraction.review_notes,
      "Removed from publication after #{to_parser} fallback-risk audit" ].compact.join("; ")
  end
  extraction.update!(attributes) if options[:apply]
  counts[passed ? "verified" : "rejected"] += 1
  puts({ extraction_id: extraction.id, document: extraction.document_canonical_id,
    action: passed ? "verified" : "rejected", applied: options[:apply] || false }.to_json)
end

puts({ audit: options[:audit].to_s, applied: options[:apply] || false, summary: counts }.to_json)
