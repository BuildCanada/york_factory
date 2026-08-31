#!/usr/bin/env ruby

require_relative "../config/environment"
require "optparse"

options = { batch_size: 100, idle_rounds: 12 }
OptionParser.new do |parser|
  parser.banner = "Usage: bin/rails runner script/review_extracted_municipal_financial_statements.rb --release VERSION [options]"
  parser.on("--release VERSION") { options[:release] = _1 }
  parser.on("--provinces LIST") { options[:provinces] = _1.split(",").map(&:strip) }
  parser.on("--limit COUNT", Integer) { options[:limit] = _1 }
  parser.on("--batch-size COUNT", Integer) { options[:batch_size] = _1 }
  parser.on("--shard INDEX/COUNT") do |value|
    options[:shard_index], options[:shard_count] = value.split("/", 2).map { Integer(_1) }
  end
  parser.on("--watch") { options[:watch] = true }
  parser.on("--idle-rounds COUNT", Integer) { options[:idle_rounds] = _1 }
  parser.on("--asset-root PATH") { options[:asset_root] = Pathname(_1).expand_path.to_s }
  parser.on("--dry-run") { options[:dry_run] = true }
  parser.on("--audit-approved-by REVIEWER") { options[:audit_approved_by] = _1 }
  parser.on("--promote-audit-approved-by REVIEWER") { options[:promote_audit_approved_by] = _1 }
  parser.on("--retry-needs-review") { options[:retry_needs_review] = true }
  parser.on("--parser-version VERSION") { options[:parser_version] = _1 }
end.parse!
abort "missing option: release" unless options[:release]
abort "--audit-approved-by cannot be combined with --watch" if options[:audit_approved_by] && options[:watch]
if options[:promote_audit_approved_by] &&
    options.values_at(:watch, :dry_run, :audit_approved_by, :retry_needs_review).any?
  abort "--promote-audit-approved-by cannot be combined with watch, dry-run, audit, or retry modes"
end
unsupported_provinces = Array(options[:provinces]) - Warehouse::FinancialStatementExtraction::CandidateSet::PROVINCES
abort "unsupported provinces: #{unsupported_provinces.join(', ')}" if unsupported_provinces.any?

release = Warehouse::InstitutionRelease.find_by!(version: options.fetch(:release))
if options[:shard_count]
  abort "shard index must be between zero and count minus one" unless options[:shard_index]&.between?(0, options[:shard_count] - 1)
end

reviewed = 0
promoted = 0
idle_rounds = 0
last_attempted_id = 0
loop do
  audit_reviewer = options[:audit_approved_by] || options[:promote_audit_approved_by]
  statuses = if audit_reviewer
    [ "approved" ]
  elsif options[:retry_needs_review]
    %w[extracted needs_review]
  else
    [ "extracted" ]
  end
  scope = release.financial_statement_extractions.where(
    extractor_version: Warehouse::FinancialStatementExtraction::DetailedPipeline::EXTRACTOR_VERSION,
    status: statuses
  ).order(:id)
  if audit_reviewer || options[:retry_needs_review]
    scope = scope.where("id > ?", last_attempted_id)
  end
  scope = scope.where(reviewed_by: audit_reviewer) if audit_reviewer
  if options[:parser_version]
    scope = scope.where("llm_response_snapshot ->> 'parser' = ?", options[:parser_version])
  end
  if options[:provinces]
    clauses = options[:provinces].map { "institution_canonical_id LIKE ?" }.join(" OR ")
    scope = scope.where(clauses, *options[:provinces].map { "ca/#{_1}/%" })
  end
  if options[:shard_count]
    scope = scope.where("MOD(id, ?) = ?", options[:shard_count], options[:shard_index])
  end
  remaining = options[:limit] && options[:limit] - reviewed
  break if remaining && remaining <= 0

  batch_limit = [ options[:batch_size], remaining ].compact.min
  batch = ActiveRecord::Base.uncached { scope.limit(batch_limit).to_a }
  if batch.empty?
    break unless options[:watch]

    idle_rounds += 1
    break if idle_rounds >= options[:idle_rounds]

    sleep 5
    next
  end

  idle_rounds = 0
  batch.each do |extraction|
    row = begin
      if options[:dry_run]
        { id: extraction.id, institution: extraction.institution_canonical_id,
          fiscal_year: extraction.fiscal_year_end.year, status: "reviewable" }
      else
        reviewer_options = { extraction: }
        reviewer_options[:asset_root] = options[:asset_root] if options[:asset_root]
        reviewer = Warehouse::FinancialStatementExtraction::Reviewer.new(**reviewer_options)
        if options[:promote_audit_approved_by]
          previous = {
            reviewed_by: extraction.reviewed_by, reviewed_at: extraction.reviewed_at&.iso8601,
            check_results: extraction.check_results
          }
          result = reviewer.reaudit!
          extraction.reload
          promoted += 1 if extraction.reviewed_by.in?(
            Warehouse::FinancialStatementExtraction::Reviewer::DETERMINISTIC_REVIEWERS
          )
          { id: extraction.id, institution: extraction.institution_canonical_id,
            fiscal_year: extraction.fiscal_year_end.year, status: result.status,
            previous:, reviewed_by: extraction.reviewed_by,
            reviewed_at: extraction.reviewed_at&.iso8601, checks: result.checks }
        else
          result = options[:audit_approved_by] ? reviewer.audit : reviewer.review!
          { id: extraction.id, institution: extraction.institution_canonical_id,
            fiscal_year: extraction.fiscal_year_end.year, status: result.status }
        end
      end
    rescue => error
      unless extraction.reviewed_at? || audit_reviewer
        extraction.update!(status: "needs_review", error_message: "review error: #{error.class}: #{error.message}")
      end
      { id: extraction.id, institution: extraction.institution_canonical_id,
        fiscal_year: extraction.fiscal_year_end.year, status: "error",
        error: "#{error.class}: #{error.message}" }
    end
    reviewed += 1
    last_attempted_id = extraction.id
    puts row.to_json
  end

  break if options[:dry_run]
end

puts({ release: release.version, dry_run: options[:dry_run] || false,
  promote_audit: options[:promote_audit_approved_by].present?, reviewed:, promoted: }.to_json)
