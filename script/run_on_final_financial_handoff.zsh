#!/bin/zsh

set -e
set -o pipefail

cd "${0:A:h}/.."

output_root=/Volumes/floppy/york_factory/public_institutions/financial-extractions
ocr_cache_root=$output_root/ocr-cache-v1
coordinator_log=$output_root/on-final-after-bounded-lanes-v2-2026-08-30.log
finite_review_log=$output_root/on-finite-review-final-v1-2026-08-30.jsonl
coverage_output=$output_root/on-final-coverage-v1-2026-08-30.json

test ! -e "$coordinator_log"
test ! -e "$finite_review_log"
test ! -e "$coverage_output"
exec > >(tee "$coordinator_log") 2>&1
export PGHOST=127.0.0.1 PGPORT=55434 PGUSER=brendansamek MUNICIPAL_FINANCIAL_OCR_CACHE_ROOT=$ocr_cache_root

polls=0
while true; do
  all_dead=1
  for session in municipal-on-head-bounded-v2 municipal-on-tail-after-nl; do
    dead=$(tmux display-message -p -t "$session":0 '#{pane_dead}' 2>/dev/null) || {
      echo "$session disappeared"
      exit 1
    }
    if test "$dead" = "1"; then
      exit_status=$(tmux display-message -p -t "$session":0 '#{pane_dead_status}')
      test "$exit_status" = "0" || { echo "$session failed with status $exit_status"; exit 1; }
    else
      all_dead=0
    fi
  done
  test "$all_dead" = "0" || break
  polls=$((polls + 1))
  test "$polls" -lt 8640 || { echo "Ontario bounded extractors timed out"; exit 1; }
  sleep 30
done

bin/rails runner 'release=Warehouse::InstitutionRelease.find_by!(version:"2026-08-27"); scope=release.financial_statement_extractions.where("institution_canonical_id LIKE ?","ca/on/%").where(extractor_version:Warehouse::FinancialStatementExtraction::DetailedPipeline::EXTRACTOR_VERSION); active=scope.where(status:%w[pending extracting]).count; abort "ON detailed pending/extracting after lanes: #{active}" unless active.zero?; puts({on_detailed_pending_extracting:0}.to_json)'
tmux kill-session -t municipal-on-review-watch-v2 2>/dev/null || true
MUNICIPAL_FINANCIAL_OCR_CONCURRENCY=1 bin/rails runner script/review_extracted_municipal_financial_statements.rb --release 2026-08-27 --provinces on --retry-needs-review --batch-size 25 2>&1 | tee "$finite_review_log"
bin/rails runner 'release=Warehouse::InstitutionRelease.find_by!(version:"2026-08-27"); scope=release.financial_statement_extractions.where("institution_canonical_id LIKE ?","ca/on/%").where(extractor_version:Warehouse::FinancialStatementExtraction::DetailedPipeline::EXTRACTOR_VERSION); active=scope.where(status:%w[pending extracting extracted]).count; abort "ON undrained detailed rows: #{active}" unless active.zero?; terminal=%w[extracted needs_review approved rejected failed]; bad=Warehouse::FinancialStatementExtraction.where(status:terminal).where("jsonb_typeof(check_results) <> ? OR jsonb_array_length(check_results)=0","array").count; abort "terminal rows without checks: #{bad}" unless bad.zero?; puts({on_detailed_pending_extracting_extracted:0,terminal_without_checks:0}.to_json)'
bin/rails runner script/audit_municipal_financial_extraction_coverage.rb --release 2026-08-27 --provinces on --output "$coverage_output"
echo "Ontario bounded extraction and finite review complete"
