#!/bin/zsh

set -e
set -o pipefail

cd "${0:A:h}/.."

output_root=/Volumes/floppy/york_factory/public_institutions/financial-extractions
ocr_cache_root=$output_root/ocr-cache-v1
coordinator_log=$output_root/ns-bc-after-atlantic-v2-2026-08-30.log
outputs=(
  $output_root/ns-generic-failed-v1-2026-08-30.jsonl
  $output_root/ns-generic-review-watch-v1-2026-08-30.jsonl
  $output_root/ns-generic-finite-review-v1-2026-08-30.jsonl
  $output_root/ns-generic-final-coverage-v1-2026-08-30.json
  $output_root/bc-generic-failed-v1-2026-08-30.jsonl
  $output_root/bc-generic-review-watch-v1-2026-08-30.jsonl
  $output_root/bc-generic-finite-review-v1-2026-08-30.jsonl
  $output_root/bc-generic-final-coverage-v1-2026-08-30.json
)

test ! -e "$coordinator_log"
for output_path in $outputs; do
  test ! -e "$output_path" || { echo "refusing existing output: $output_path"; exit 1; }
done

exec > >(tee "$coordinator_log") 2>&1
export PGHOST=127.0.0.1 PGPORT=55434 PGUSER=brendansamek MUNICIPAL_FINANCIAL_OCR_CACHE_ROOT=$ocr_cache_root MUNICIPAL_FINANCIAL_DETAIL_FLOW_CONCURRENCY=2

polls=0
while true; do
  dead=$(tmux display-message -p -t municipal-atlantic-nb-pe-after-mb-v2:0 '#{pane_dead}' 2>/dev/null) || {
    echo "Atlantic coordinator disappeared"
    exit 1
  }
  if test "$dead" = "1"; then
    exit_status=$(tmux display-message -p -t municipal-atlantic-nb-pe-after-mb-v2:0 '#{pane_dead_status}')
    test "$exit_status" = "0" || {
      echo "Atlantic coordinator failed with status $exit_status"
      exit 1
    }
    break
  fi
  polls=$((polls + 1))
  test "$polls" -lt 20160 || { echo "Atlantic coordinator wait timed out"; exit 1; }
  sleep 30
done

pane_alive() {
  tmux list-panes -t "$1" -F '#{pane_dead}' 2>/dev/null | rg -qx '0'
}

drain_province() {
  province="$1"
  reviewer_session="$2"
  polls=0
  while true; do
    state=$(bin/rails runner "release=Warehouse::InstitutionRelease.find_by!(version:'2026-08-27'); scope=release.financial_statement_extractions.where('institution_canonical_id LIKE ?', 'ca/${province}/%').where(extractor_version:Warehouse::FinancialStatementExtraction::DetailedPipeline::EXTRACTOR_VERSION); active=scope.where(status:%w[pending extracting]).count; extracted=scope.where(status:'extracted').count; puts \"#{active}:#{extracted}\"" | tail -n 1)
    active="${state%%:*}"
    extracted="${state##*:}"
    test "$active" = "0" || { echo "$province active rows after extractor: $active"; exit 1; }
    if test "$extracted" = "0"; then
      echo "$province reviewer drain complete"
      return
    fi
    pane_alive "$reviewer_session" || { echo "$reviewer_session died with $extracted extracted rows"; exit 1; }
    polls=$((polls + 1))
    test "$polls" -lt 1440 || { echo "$province reviewer drain timed out with $extracted rows"; exit 1; }
    echo "$province waiting for reviewer: $extracted extracted rows"
    sleep 30
  done
}

assert_terminal_checks() {
  bin/rails runner 'terminal=%w[extracted needs_review approved rejected failed]; bad=Warehouse::FinancialStatementExtraction.where(status:terminal).where("jsonb_typeof(check_results) <> ? OR jsonb_array_length(check_results)=0","array").count; abort "terminal rows without checks: #{bad}" unless bad.zero?; puts({terminal_without_checks:0}.to_json)'
}

assert_terminal_checks
ns_baseline=$(bin/rails runner 'release=Warehouse::InstitutionRelease.find_by!(version:"2026-08-27"); candidates=Warehouse::FinancialStatementExtraction::CandidateSet.new(release:,provinces:["ns"]).each.to_a; filter=Warehouse::FinancialStatementExtraction::FailedCandidateFilter.new(release:,province:"ns",candidates:); report=filter.report; abort "NS filter changed: #{report.slice(:public_slot_count,:unmatched_failure_count,:reconciled).inspect}" unless report.fetch(:public_slot_count)==355 && report.fetch(:unmatched_failure_count).zero? && report.fetch(:reconciled); totals=Warehouse::FinancialStatementExtraction::CoverageAudit.new(release:,provinces:["ns"]).payload.fetch(:totals); active=release.financial_statement_extractions.where("institution_canonical_id LIKE ?","ca/ns/%").where(extractor_version:Warehouse::FinancialStatementExtraction::DetailedPipeline::EXTRACTOR_VERSION,status:%w[pending extracting extracted]).count; abort "NS active detailed rows: #{active}" unless active.zero?; puts totals.fetch(:published_institution_year_count)' | tail -n 1)
echo "NS preflight selected=355 baseline_published=$ns_baseline; new path=deterministic prairie-v3 with generic DetailedPipeline fallback on Unsupported"

tmux has-session -t municipal-ns-generic-review-v1 2>/dev/null && { echo "NS reviewer exists"; exit 1; }
tmux new-session -d -s municipal-ns-generic-review-v1 -c "$PWD" "set -o pipefail; PGHOST=127.0.0.1 PGPORT=55434 PGUSER=brendansamek MUNICIPAL_FINANCIAL_OCR_CACHE_ROOT=$ocr_cache_root MUNICIPAL_FINANCIAL_OCR_CONCURRENCY=1 bin/rails runner script/review_extracted_municipal_financial_statements.rb --release 2026-08-27 --provinces ns --batch-size 25 --watch --idle-rounds 25920 2>&1 | tee $output_root/ns-generic-review-watch-v1-2026-08-30.jsonl"
MUNICIPAL_FINANCIAL_OCR_CONCURRENCY=2 bin/rails runner script/process_municipal_financial_statements.rb --release 2026-08-27 --province ns --rerun failed --failed-only 2>&1 | tee $output_root/ns-generic-failed-v1-2026-08-30.jsonl
drain_province ns municipal-ns-generic-review-v1
tmux kill-session -t municipal-ns-generic-review-v1 2>/dev/null || true
MUNICIPAL_FINANCIAL_OCR_CONCURRENCY=1 bin/rails runner script/review_extracted_municipal_financial_statements.rb --release 2026-08-27 --provinces ns --retry-needs-review --batch-size 25 2>&1 | tee $output_root/ns-generic-finite-review-v1-2026-08-30.jsonl
assert_terminal_checks
bin/rails runner script/audit_municipal_financial_extraction_coverage.rb --release 2026-08-27 --provinces ns --output $output_root/ns-generic-final-coverage-v1-2026-08-30.json

ns_gate=$(NS_BASELINE="$ns_baseline" bin/rails runner 'release=Warehouse::InstitutionRelease.find_by!(version:"2026-08-27"); totals=Warehouse::FinancialStatementExtraction::CoverageAudit.new(release:,provinces:["ns"]).payload.fetch(:totals); active=release.financial_statement_extractions.where("institution_canonical_id LIKE ?","ca/ns/%").where(extractor_version:Warehouse::FinancialStatementExtraction::DetailedPipeline::EXTRACTOR_VERSION,status:%w[pending extracting extracted]).count; abort "NS undrained detailed rows: #{active}" unless active.zero?; published=totals.fetch(:published_institution_year_count); delta=published-Integer(ENV.fetch("NS_BASELINE")); needs=totals.fetch(:status_counts).fetch("needs_review",0); puts "#{published}:#{delta}:#{needs}"' | tail -n 1)
IFS=: read ns_published ns_delta ns_needs <<< "$ns_gate"
echo "NS gate published=$ns_published delta=$ns_delta needs_review=$ns_needs required_delta=71"
if test "$ns_delta" -lt 71; then
  echo "NS gate failed; BC is intentionally not started; inspect NS and BC failure clusters"
  exit 3
fi

bc_baseline=$(bin/rails runner 'release=Warehouse::InstitutionRelease.find_by!(version:"2026-08-27"); candidates=Warehouse::FinancialStatementExtraction::CandidateSet.new(release:,provinces:["bc"]).each.to_a; filter=Warehouse::FinancialStatementExtraction::FailedCandidateFilter.new(release:,province:"bc",candidates:); report=filter.report; abort "BC filter changed: #{report.slice(:public_slot_count,:unmatched_failure_count,:reconciled).inspect}" unless report.fetch(:public_slot_count)==1100 && report.fetch(:unmatched_failure_count).zero? && report.fetch(:reconciled); totals=Warehouse::FinancialStatementExtraction::CoverageAudit.new(release:,provinces:["bc"]).payload.fetch(:totals); active=release.financial_statement_extractions.where("institution_canonical_id LIKE ?","ca/bc/%").where(extractor_version:Warehouse::FinancialStatementExtraction::DetailedPipeline::EXTRACTOR_VERSION,status:%w[pending extracting extracted]).count; abort "BC active detailed rows: #{active}" unless active.zero?; puts totals.fetch(:published_institution_year_count)' | tail -n 1)
echo "BC gate passed via NS; baseline_published=$bc_baseline selected=1100"

tmux has-session -t municipal-bc-generic-review-v1 2>/dev/null && { echo "BC reviewer exists"; exit 1; }
tmux new-session -d -s municipal-bc-generic-review-v1 -c "$PWD" "set -o pipefail; PGHOST=127.0.0.1 PGPORT=55434 PGUSER=brendansamek MUNICIPAL_FINANCIAL_OCR_CACHE_ROOT=$ocr_cache_root MUNICIPAL_FINANCIAL_OCR_CONCURRENCY=1 bin/rails runner script/review_extracted_municipal_financial_statements.rb --release 2026-08-27 --provinces bc --batch-size 25 --watch --idle-rounds 25920 2>&1 | tee $output_root/bc-generic-review-watch-v1-2026-08-30.jsonl"
MUNICIPAL_FINANCIAL_OCR_CONCURRENCY=2 bin/rails runner script/process_municipal_financial_statements.rb --release 2026-08-27 --province bc --rerun failed --failed-only 2>&1 | tee $output_root/bc-generic-failed-v1-2026-08-30.jsonl
drain_province bc municipal-bc-generic-review-v1
tmux kill-session -t municipal-bc-generic-review-v1 2>/dev/null || true
MUNICIPAL_FINANCIAL_OCR_CONCURRENCY=1 bin/rails runner script/review_extracted_municipal_financial_statements.rb --release 2026-08-27 --provinces bc --retry-needs-review --batch-size 25 2>&1 | tee $output_root/bc-generic-finite-review-v1-2026-08-30.jsonl
assert_terminal_checks
bin/rails runner script/audit_municipal_financial_extraction_coverage.rb --release 2026-08-27 --provinces bc --output $output_root/bc-generic-final-coverage-v1-2026-08-30.json
bin/rails runner 'release=Warehouse::InstitutionRelease.find_by!(version:"2026-08-27"); scope=release.financial_statement_extractions.where("institution_canonical_id LIKE ?","ca/bc/%").where(extractor_version:Warehouse::FinancialStatementExtraction::DetailedPipeline::EXTRACTOR_VERSION); active=scope.where(status:%w[pending extracting extracted]).count; abort "BC undrained detailed rows: #{active}" unless active.zero?; puts({bc_detailed_pending_extracting_extracted:0}.to_json)'
echo "NS and BC generic fallback cycles complete"
