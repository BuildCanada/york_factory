#!/bin/zsh

set -e
set -o pipefail

cd "${0:A:h}/.."

output_root=/Volumes/floppy/york_factory/public_institutions/financial-extractions
ocr_cache_root=$output_root/ocr-cache-v1
coordinator_log=$output_root/territories-after-nl-v1-2026-08-30.log
outputs=(
  $output_root/nt-finite-review-before-retry-v1-2026-08-30.jsonl
  $output_root/yt-finite-review-v1-2026-08-30.jsonl
  $output_root/nt-generic-failed-v1-2026-08-30.jsonl
  $output_root/nt-finite-review-after-retry-v1-2026-08-30.jsonl
  $output_root/nt-final-coverage-v1-2026-08-30.json
  $output_root/yt-final-coverage-v1-2026-08-30.json
  $output_root/nu-final-coverage-v1-2026-08-30.json
)

test ! -e "$coordinator_log"
for output_path in $outputs; do
  test ! -e "$output_path" || { echo "refusing existing output: $output_path"; exit 1; }
done
exec > >(tee "$coordinator_log") 2>&1
export PGHOST=127.0.0.1 PGPORT=55434 PGUSER=brendansamek MUNICIPAL_FINANCIAL_OCR_CACHE_ROOT=$ocr_cache_root

polls=0
while true; do
  dead=$(tmux display-message -p -t municipal-nl-retry-review-after-v2:0 '#{pane_dead}' 2>/dev/null) || {
    echo "NL coordinator disappeared"
    exit 1
  }
  if test "$dead" = "1"; then
    exit_status=$(tmux display-message -p -t municipal-nl-retry-review-after-v2:0 '#{pane_dead_status}')
    test "$exit_status" = "0" || { echo "NL coordinator failed with status $exit_status"; exit 1; }
    break
  fi
  polls=$((polls + 1))
  test "$polls" -lt 8640 || { echo "NL coordinator wait timed out"; exit 1; }
  sleep 30
done

bin/rails runner 'release=Warehouse::InstitutionRelease.find_by!(version:"2026-08-27"); version=Warehouse::FinancialStatementExtraction::DetailedPipeline::EXTRACTOR_VERSION; expected={"nt"=>{"approved"=>17,"needs_review"=>9,"failed"=>2},"yt"=>{"approved"=>22,"needs_review"=>18},"nu"=>{"approved"=>15}}; expected.each do |province,statuses|; totals=Warehouse::FinancialStatementExtraction::CoverageAudit.new(release:,provinces:[province]).payload.fetch(:totals); abort "#{province.upcase} preflight changed: #{totals.fetch(:status_counts).inspect}" unless totals.fetch(:status_counts)==statuses; abort "#{province.upcase} checks/provenance failed" unless totals.fetch(:approved_without_checks).zero? && totals.fetch(:approved_without_deterministic_reviewer).zero?; active=release.financial_statement_extractions.where("institution_canonical_id LIKE ?","ca/#{province}/%").where(extractor_version:version,status:%w[pending extracting extracted]).count; abort "#{province.upcase} active detailed rows: #{active}" unless active.zero?; end; puts({territory_preflight:"pass",statuses:expected}.to_json)'

MUNICIPAL_FINANCIAL_OCR_CONCURRENCY=1 bin/rails runner script/review_extracted_municipal_financial_statements.rb --release 2026-08-27 --provinces nt --retry-needs-review --batch-size 25 2>&1 | tee $output_root/nt-finite-review-before-retry-v1-2026-08-30.jsonl
MUNICIPAL_FINANCIAL_OCR_CONCURRENCY=1 bin/rails runner script/review_extracted_municipal_financial_statements.rb --release 2026-08-27 --provinces yt --retry-needs-review --batch-size 25 2>&1 | tee $output_root/yt-finite-review-v1-2026-08-30.jsonl

bin/rails runner 'release=Warehouse::InstitutionRelease.find_by!(version:"2026-08-27"); candidates=Warehouse::FinancialStatementExtraction::CandidateSet.new(release:,provinces:["nt"]).each.to_a; report=Warehouse::FinancialStatementExtraction::FailedCandidateFilter.new(release:,province:"nt",candidates:).report; covered=report.fetch(:approved_elsewhere_excluded_count)+report.fetch(:review_pending_elsewhere_excluded_count); abort "NT failed filter changed: #{report.slice(:aggregated_failure_count,:public_slot_count,:approved_elsewhere_excluded_count,:review_pending_elsewhere_excluded_count,:duplicate_slot_excluded_count,:unmatched_failure_count,:reconciled).inspect}" unless report.fetch(:aggregated_failure_count)==2 && report.fetch(:public_slot_count)+covered==2 && report.fetch(:duplicate_slot_excluded_count).zero? && report.fetch(:unmatched_failure_count).zero? && report.fetch(:reconciled); puts({nt_failed_filter:report.except(:approved_elsewhere_excluded,:review_pending_elsewhere_excluded,:duplicate_slot_excluded,:unmatched_failures)}.to_json)'
bin/rails runner script/process_municipal_financial_statements.rb --release 2026-08-27 --province nt --rerun failed --failed-only 2>&1 | tee $output_root/nt-generic-failed-v1-2026-08-30.jsonl
MUNICIPAL_FINANCIAL_OCR_CONCURRENCY=1 bin/rails runner script/review_extracted_municipal_financial_statements.rb --release 2026-08-27 --provinces nt --retry-needs-review --batch-size 25 2>&1 | tee $output_root/nt-finite-review-after-retry-v1-2026-08-30.jsonl

bin/rails runner 'release=Warehouse::InstitutionRelease.find_by!(version:"2026-08-27"); version=Warehouse::FinancialStatementExtraction::DetailedPipeline::EXTRACTOR_VERSION; %w[nt yt].each do |province|; scope=release.financial_statement_extractions.where("institution_canonical_id LIKE ?","ca/#{province}/%").where(extractor_version:version); active=scope.where(status:%w[pending extracting extracted]).count; abort "#{province.upcase} undrained detailed rows: #{active}" unless active.zero?; end; nu=Warehouse::FinancialStatementExtraction::CoverageAudit.new(release:,provinces:["nu"]).payload.fetch(:totals); abort "NU changed: #{nu.fetch(:status_counts).inspect}" unless nu.fetch(:preferred_asset_count)==15 && nu.fetch(:published_institution_year_count)==15 && nu.fetch(:status_counts)=={"approved"=>15} && nu.fetch(:approved_without_checks).zero? && nu.fetch(:approved_without_deterministic_reviewer).zero?; terminal=%w[extracted needs_review approved rejected failed]; bad=Warehouse::FinancialStatementExtraction.where(status:terminal).where("jsonb_typeof(check_results) <> ? OR jsonb_array_length(check_results)=0","array").count; abort "terminal rows without checks: #{bad}" unless bad.zero?; puts({territories_drained:true,nu_approved:15,terminal_without_checks:0}.to_json)'
bin/rails runner script/audit_municipal_financial_extraction_coverage.rb --release 2026-08-27 --provinces nt --output $output_root/nt-final-coverage-v1-2026-08-30.json
bin/rails runner script/audit_municipal_financial_extraction_coverage.rb --release 2026-08-27 --provinces yt --output $output_root/yt-final-coverage-v1-2026-08-30.json
bin/rails runner script/audit_municipal_financial_extraction_coverage.rb --release 2026-08-27 --provinces nu --output $output_root/nu-final-coverage-v1-2026-08-30.json
echo "Territory extraction, review, and per-record audits complete"
