#!/usr/bin/env ruby

require_relative "../config/environment"
require "optparse"

options = { provinces: Warehouse::FinancialStatementExtraction::CandidateSet::PROVINCES, rerun: "missing" }
OptionParser.new do |parser|
  parser.banner = "Usage: bin/rails runner script/enqueue_municipal_financial_extractions.rb --release VERSION [options]"
  parser.on("--release VERSION") { options[:release] = _1 }
  parser.on("--provinces LIST") { options[:provinces] = _1.split(",").map(&:strip) }
  parser.on("--years LIST") { options[:years] = _1.split(",").map { Integer(it) } }
  parser.on("--institution-ids LIST") { options[:institution_ids] = _1.split(",").map(&:strip) }
  parser.on("--limit COUNT", Integer) { options[:limit] = _1 }
  parser.on("--rerun POLICY", Warehouse::FinancialStatementExtraction::Processor::RERUN_POLICIES) { options[:rerun] = _1 }
  parser.on("--asset-root PATH") { options[:asset_root] = Pathname(_1).expand_path.to_s }
  parser.on("--dry-run") { options[:dry_run] = true }
  parser.on("--verify-hashes") { options[:verify_hashes] = true }
end.parse!
abort "missing option: release" unless options[:release]

release = Warehouse::InstitutionRelease.find_by!(version: options.fetch(:release))
results = options.fetch(:provinces).to_h do |province|
  candidate_options = {
    release:, provinces: [ province ], years: options[:years],
    institution_ids: options[:institution_ids]
  }
  candidate_options[:asset_root] = options[:asset_root] if options[:asset_root]
  candidates = Warehouse::FinancialStatementExtraction::CandidateSet.new(**candidate_options)
  if options[:dry_run]
    audit = candidates.audit(verify_hashes: options[:verify_hashes])
    [ province, audit ]
  else
    job_options = {
      province:, years: options[:years], institution_ids: options[:institution_ids],
      limit: options[:limit], rerun: options.fetch(:rerun), asset_root: options[:asset_root]
    }.compact
    job = Warehouse::ExtractMunicipalFinancialStatementsJob.perform_later(release.version, **job_options)
    [ province, { candidates: candidates.count, job_id: job.job_id } ]
  end
end

puts JSON.pretty_generate(release: release.version, dry_run: options[:dry_run] || false, provinces: results)
