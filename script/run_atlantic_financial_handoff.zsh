#!/bin/zsh

set -e
set -o pipefail

cd "${0:A:h}/.."

output_root=/Volumes/floppy/york_factory/public_institutions/financial-extractions
ocr_cache_root=$output_root/ocr-cache-v1
handoff_log=$output_root/atlantic-nb-pe-after-mb-v2-2026-08-30.log

test ! -e "$handoff_log"
exec > >(tee "$handoff_log") 2>&1
export PGHOST=127.0.0.1 PGPORT=55434 PGUSER=brendansamek MUNICIPAL_FINANCIAL_OCR_CACHE_ROOT=$ocr_cache_root

reviewer_alive() {
  tmux list-panes -t "$1" -F '#{pane_dead}' 2>/dev/null | rg -qx '0'
}

drain_review() {
  province="$1"
  reviewer_session="$2"
  polls=0
  while true; do
    state=$(bin/rails runner "release=Warehouse::InstitutionRelease.find_by!(version:'2026-08-27'); scope=release.financial_statement_extractions.where('institution_canonical_id LIKE ?', 'ca/${province}/%'); active=scope.where(status:%w[pending extracting]).count; extracted=scope.where(extractor_version:Warehouse::FinancialStatementExtraction::DetailedPipeline::EXTRACTOR_VERSION,status:'extracted').count; puts \"#{active}:#{extracted}\"" | tail -n 1)
    active="${state%%:*}"
    extracted="${state##*:}"
    test "$active" = "0" || { echo "$province active rows after extractor: $active"; exit 1; }
    if test "$extracted" = "0"; then
      echo "$province reviewer drain complete"
      return
    fi
    reviewer_alive "$reviewer_session" || { echo "$reviewer_session died with $extracted extracted rows"; exit 1; }
    polls=$((polls + 1))
    test "$polls" -lt 720 || { echo "$province reviewer drain timed out with $extracted extracted rows"; exit 1; }
    echo "$province waiting for reviewer: $extracted extracted rows"
    sleep 30
  done
}

assert_terminal_checks() {
  bin/rails runner 'terminal=%w[extracted needs_review approved rejected failed]; bad=Warehouse::FinancialStatementExtraction.where(status:terminal).where("jsonb_typeof(check_results) <> ? OR jsonb_array_length(check_results)=0","array").count; abort "terminal rows without checks: #{bad}" unless bad.zero?; puts({terminal_without_checks:0}.to_json)'
}

current_load() {
  sysctl -n vm.loadavg | awk '{ print $2 }'
}

load_monitor_pid=
stop_load_monitor() {
  if test -n "$load_monitor_pid"; then
    kill "$load_monitor_pid" 2>/dev/null || true
    wait "$load_monitor_pid" 2>/dev/null || true
    load_monitor_pid=
  fi
}

start_load_monitor() {
  label="$1"
  (
    while sleep 60; do
      load=$(current_load)
      if awk -v load="$load" 'BEGIN { exit !(load > 15) }'; then
        echo "{\"load_alert\":\"$label\",\"one_minute_load\":$load,\"action\":\"alert_only\",\"recovery\":\"SIGTERM the producer, run the logged stale-extracting sweep, then relaunch this coordinator\"}"
      fi
    done
  ) &
  load_monitor_pid=$!
}

trap stop_load_monitor EXIT INT TERM

startup_load=$(current_load)
if awk -v load="$startup_load" 'BEGIN { exit !(load > 15) }'; then
  echo "Atlantic early-start load gate failed: one-minute load $startup_load exceeds 15"
  exit 3
fi

assert_terminal_checks
bin/rails runner 'release=Warehouse::InstitutionRelease.find_by!(version:"2026-08-27"); totals=Warehouse::FinancialStatementExtraction::CoverageAudit.new(release:,provinces:["nb"]).payload.fetch(:totals); expected={"unattempted"=>240,"shared_asset"=>9}; abort "NB prelane changed: #{totals.fetch(:status_counts).inspect}" unless totals.fetch(:status_counts)==expected; scope=release.financial_statement_extractions.where("institution_canonical_id LIKE ?","ca/nb/%"); active=scope.where(status:%w[pending extracting]).count; abort "NB active rows: #{active}" unless active.zero?; puts({preflight:"pass",province:"nb",statuses:expected}.to_json)'
tmux has-session -t municipal-nb-review-watch-v1 2>/dev/null && { echo "NB reviewer already exists"; exit 1; }
tmux new-session -d -s municipal-nb-review-watch-v1 -c "$PWD" "set -o pipefail; PGHOST=127.0.0.1 PGPORT=55434 PGUSER=brendansamek MUNICIPAL_FINANCIAL_OCR_CACHE_ROOT=$ocr_cache_root MUNICIPAL_FINANCIAL_OCR_CONCURRENCY=1 bin/rails runner script/review_extracted_municipal_financial_statements.rb --release 2026-08-27 --provinces nb --retry-needs-review --batch-size 25 --watch --idle-rounds 1440 2>&1 | tee $output_root/nb-review-watch-v1-2026-08-30.jsonl"
start_load_monitor nb
MUNICIPAL_FINANCIAL_OCR_CONCURRENCY=1 bin/rails runner script/process_municipal_financial_statements.rb --release 2026-08-27 --province nb --rerun missing 2>&1 | tee $output_root/nb-full-missing-v1-2026-08-30.jsonl
stop_load_monitor
drain_review nb municipal-nb-review-watch-v1
assert_terminal_checks
bin/rails runner script/audit_municipal_financial_extraction_coverage.rb --release 2026-08-27 --provinces nb --output $output_root/nb-final-coverage-v1-2026-08-30.json

bin/rails runner 'release=Warehouse::InstitutionRelease.find_by!(version:"2026-08-27"); totals=Warehouse::FinancialStatementExtraction::CoverageAudit.new(release:,provinces:["pe"]).payload.fetch(:totals); expected={"headline_pending"=>3,"headline_needs_review"=>10,"needs_review"=>1,"unattempted"=>165}; abort "PE prelane changed: #{totals.fetch(:status_counts).inspect}" unless totals.fetch(:status_counts)==expected; detailed=release.financial_statement_extractions.where("institution_canonical_id LIKE ?","ca/pe/%").where(extractor_version:Warehouse::FinancialStatementExtraction::DetailedPipeline::EXTRACTOR_VERSION,status:%w[pending extracting]).count; abort "PE detailed active rows: #{detailed}" unless detailed.zero?; puts({preflight:"pass",province:"pe",statuses:expected,detailed_active:0}.to_json)'
tmux has-session -t municipal-pe-review-watch-v1 2>/dev/null && { echo "PE reviewer already exists"; exit 1; }
tmux new-session -d -s municipal-pe-review-watch-v1 -c "$PWD" "set -o pipefail; PGHOST=127.0.0.1 PGPORT=55434 PGUSER=brendansamek MUNICIPAL_FINANCIAL_OCR_CACHE_ROOT=$ocr_cache_root MUNICIPAL_FINANCIAL_OCR_CONCURRENCY=1 bin/rails runner script/review_extracted_municipal_financial_statements.rb --release 2026-08-27 --provinces pe --retry-needs-review --batch-size 25 --watch --idle-rounds 1440 2>&1 | tee $output_root/pe-review-watch-v1-2026-08-30.jsonl"
start_load_monitor pe
MUNICIPAL_FINANCIAL_OCR_CONCURRENCY=1 bin/rails runner script/process_municipal_financial_statements.rb --release 2026-08-27 --province pe --rerun missing 2>&1 | tee $output_root/pe-full-missing-v1-2026-08-30.jsonl
stop_load_monitor
drain_review pe municipal-pe-review-watch-v1
assert_terminal_checks
bin/rails runner script/audit_municipal_financial_extraction_coverage.rb --release 2026-08-27 --provinces pe --output $output_root/pe-final-coverage-v1-2026-08-30.json

while kill -0 8058 2>/dev/null; do
  sleep 30
done
drain_review mb municipal-mb-review-watch-v1
assert_terminal_checks
echo "Atlantic NB/PE handoff complete"
