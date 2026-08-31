#!/bin/zsh

set -e
set -o pipefail

cd "${0:A:h}/.."

output_root=/Volumes/floppy/york_factory/public_institutions/financial-extractions
ocr_cache_root=$output_root/ocr-cache-v1
manifest=$output_root/qc-generic-fallback-canary-manifest-v1-2026-08-30.json
coordinator_log=$output_root/qc-generic-fallback-after-on-v1-2026-08-30.log
canary_results=$output_root/qc-generic-fallback-canary-results-v1-2026-08-30.json
outputs=(
  $output_root/qc-finite-review-before-fallback-v1-2026-08-30.jsonl
  $output_root/qc-generic-fallback-canary-v1-2026-08-30.jsonl
  $output_root/qc-generic-fallback-canary-review-watch-v1-2026-08-30.jsonl
  $output_root/qc-generic-fallback-canary-finite-review-v1-2026-08-30.jsonl
  $canary_results
  $output_root/qc-generic-fallback-remainder-v1-2026-08-30.jsonl
  $output_root/qc-generic-fallback-remainder-review-watch-v1-2026-08-30.jsonl
  $output_root/qc-generic-fallback-remainder-finite-review-v1-2026-08-30.jsonl
  $output_root/qc-generic-fallback-final-coverage-v1-2026-08-30.json
)

test -f "$manifest"
test ! -e "$coordinator_log"
for output_path in $outputs; do
  test ! -e "$output_path" || { echo "refusing existing output: $output_path"; exit 1; }
done
exec > >(tee "$coordinator_log") 2>&1
export PGHOST=127.0.0.1 PGPORT=55434 PGUSER=brendansamek MUNICIPAL_FINANCIAL_OCR_CACHE_ROOT=$ocr_cache_root MUNICIPAL_FINANCIAL_DETAIL_FLOW_CONCURRENCY=2

polls=0
while true; do
  dead=$(tmux display-message -p -t municipal-on-final-after-bounded-lanes-v2:0 '#{pane_dead}' 2>/dev/null) || {
    echo "Ontario final coordinator disappeared"
    exit 1
  }
  if test "$dead" = "1"; then
    exit_status=$(tmux display-message -p -t municipal-on-final-after-bounded-lanes-v2:0 '#{pane_dead_status}')
    test "$exit_status" = "0" || { echo "Ontario final coordinator failed with status $exit_status"; exit 1; }
    break
  fi
  polls=$((polls + 1))
  test "$polls" -lt 20160 || { echo "Ontario final coordinator wait timed out"; exit 1; }
  sleep 30
done

pane_alive() {
  tmux list-panes -t "$1" -F '#{pane_dead}' 2>/dev/null | rg -qx '0'
}

drain_qc() {
  reviewer_session="$1"
  polls=0
  while true; do
    state=$(bin/rails runner 'release=Warehouse::InstitutionRelease.find_by!(version:"2026-08-27"); scope=release.financial_statement_extractions.where("institution_canonical_id LIKE ?","ca/qc/%").where(extractor_version:Warehouse::FinancialStatementExtraction::DetailedPipeline::EXTRACTOR_VERSION); active=scope.where(status:%w[pending extracting]).count; extracted=scope.where(status:"extracted").count; puts "#{active}:#{extracted}"' | tail -n 1)
    active="${state%%:*}"
    extracted="${state##*:}"
    test "$active" = "0" || { echo "QC active rows after extractor: $active"; exit 1; }
    if test "$extracted" = "0"; then
      echo "QC reviewer drain complete"
      return
    fi
    pane_alive "$reviewer_session" || { echo "$reviewer_session died with $extracted extracted rows"; exit 1; }
    polls=$((polls + 1))
    test "$polls" -lt 1440 || { echo "QC reviewer drain timed out with $extracted rows"; exit 1; }
    echo "QC waiting for reviewer: $extracted extracted rows"
    sleep 30
  done
}

assert_terminal_checks() {
  bin/rails runner 'terminal=%w[extracted needs_review approved rejected failed]; bad=Warehouse::FinancialStatementExtraction.where(status:terminal).where("jsonb_typeof(check_results) <> ? OR jsonb_array_length(check_results)=0","array").count; abort "terminal rows without checks: #{bad}" unless bad.zero?; puts({terminal_without_checks:0}.to_json)'
}

tmux kill-session -t municipal-qc-preform-review-v1 2>/dev/null || true
MUNICIPAL_FINANCIAL_OCR_CONCURRENCY=1 bin/rails runner script/review_extracted_municipal_financial_statements.rb --release 2026-08-27 --provinces qc --retry-needs-review --batch-size 25 2>&1 | tee $output_root/qc-finite-review-before-fallback-v1-2026-08-30.jsonl
assert_terminal_checks

canary_ids=$(MANIFEST="$manifest" bin/rails runner 'require "digest"; manifest=JSON.parse(File.read(ENV.fetch("MANIFEST"))); ids=manifest.fetch("document_ids").map { Integer(_1) }; expected={"position_net+position_surplus"=>16,"surplus_rollforward"=>9,"position-statement-not-found"=>7,"long-tail"=>18}; abort "manifest size" unless ids.length==50 && ids.uniq.length==50; abort "manifest checksum" unless Digest::SHA256.hexdigest(ids.join(","))=="ddf22a15cd12a32fcfab0ee303f6a0c28d45d4d5520fc410d3dd44ae26b8d834"; abort "manifest composition" unless manifest.fetch("records").map { _1.fetch("cluster") }.tally==expected; release=Warehouse::InstitutionRelease.find_by!(version:"2026-08-27"); candidates=Warehouse::FinancialStatementExtraction::CandidateSet.new(release:,provinces:["qc"]).each.to_a; filter=Warehouse::FinancialStatementExtraction::FailedCandidateFilter.new(release:,province:"qc",candidates:,parser_versions:["quebec-mamh-form-v1"]); report=filter.report; abort "target filter changed: #{report.slice(:aggregated_failure_count,:public_slot_count,:unmatched_failure_count,:reconciled).inspect}" unless report.fetch(:aggregated_failure_count)==719 && report.fetch(:public_slot_count)==719 && report.fetch(:unmatched_failure_count).zero? && report.fetch(:reconciled); eligible=candidates.select { filter.eligible?(_1) }.index_by(&:document_id); detailed=release.financial_statement_extractions.where(extractor_version:Warehouse::FinancialStatementExtraction::DetailedPipeline::EXTRACTOR_VERSION); extractions=detailed.index_by { [_1.asset_sha256,_1.fiscal_year_end] }; manifest.fetch("records").each do |record|; candidate=eligible.fetch(Integer(record.fetch("document_id"))); extraction=extractions.fetch([candidate.asset_sha256,candidate.fiscal_year_end]); abort "canary identity drift" unless extraction.status=="failed" && extraction.llm_response_snapshot&.fetch("parser",nil)=="quebec-mamh-form-v1" && extraction.error_message==record.fetch("error"); end; active=detailed.where("institution_canonical_id LIKE ?","ca/qc/%").where(status:%w[pending extracting extracted]).count; abort "QC active detailed rows: #{active}" unless active.zero?; puts ids.join(",")' | tail -n 1)
echo "QC canary manifest revalidated: 50 targeted failures"

tmux has-session -t municipal-qc-generic-canary-review-v1 2>/dev/null && { echo "QC canary reviewer exists"; exit 1; }
tmux new-session -d -s municipal-qc-generic-canary-review-v1 -c "$PWD" "set -o pipefail; PGHOST=127.0.0.1 PGPORT=55434 PGUSER=brendansamek MUNICIPAL_FINANCIAL_OCR_CACHE_ROOT=$ocr_cache_root MUNICIPAL_FINANCIAL_OCR_CONCURRENCY=1 bin/rails runner script/review_extracted_municipal_financial_statements.rb --release 2026-08-27 --provinces qc --batch-size 25 --watch --idle-rounds 25920 2>&1 | tee $output_root/qc-generic-fallback-canary-review-watch-v1-2026-08-30.jsonl"
MUNICIPAL_FINANCIAL_OCR_CONCURRENCY=2 bin/rails runner script/process_municipal_financial_statements.rb --release 2026-08-27 --province qc --rerun failed --failed-only --failed-parser quebec-mamh-form-v1 --document-ids "$canary_ids" 2>&1 | tee $output_root/qc-generic-fallback-canary-v1-2026-08-30.jsonl
drain_qc municipal-qc-generic-canary-review-v1
tmux kill-session -t municipal-qc-generic-canary-review-v1 2>/dev/null || true
MUNICIPAL_FINANCIAL_OCR_CONCURRENCY=1 bin/rails runner script/review_extracted_municipal_financial_statements.rb --release 2026-08-27 --provinces qc --retry-needs-review --batch-size 25 2>&1 | tee $output_root/qc-generic-fallback-canary-finite-review-v1-2026-08-30.jsonl
assert_terminal_checks

MANIFEST="$manifest" bin/rails runner 'manifest=JSON.parse(File.read(ENV.fetch("MANIFEST"))); release=Warehouse::InstitutionRelease.find_by!(version:"2026-08-27"); version=Warehouse::FinancialStatementExtraction::DetailedPipeline::EXTRACTOR_VERSION; records=manifest.fetch("records").map do |record|; extraction=release.financial_statement_extractions.find_by!(asset_sha256:record.fetch("asset_sha256"),fiscal_year_end:Date.iso8601(record.fetch("fiscal_year_end")),extractor_version:version); record.slice("document_id","document_canonical_id","institution_canonical_id","cluster").merge(status:extraction.status,extraction_id:extraction.id,reviewed_by:extraction.reviewed_by,reviewed_at:extraction.reviewed_at&.iso8601,fact_count:extraction.financial_statement_facts.count,line_item_count:extraction.financial_statement_line_items.count,verification:Warehouse::FinancialStatementExtraction.verification_checks(extraction.check_results),error:extraction.error_message); end; by_cluster=records.group_by { _1.fetch("cluster") }.transform_values { |rows| rows.map { _1.fetch(:status) }.tally }; puts({release:release.version,generated_at:Time.current.iso8601,gate:{required_approved:10,attempted:50},status_counts:records.map { _1.fetch(:status) }.tally,cluster_status_counts:by_cluster,records:}.to_json)' | tail -n 1 | tee "$canary_results"
gate=$(ruby -rjson -e 'payload=JSON.parse(File.read(ARGV.fetch(0))); counts=payload.fetch("status_counts"); puts [counts.fetch("approved",0),counts.fetch("needs_review",0),counts.fetch("failed",0)].join(":")' "$canary_results")
IFS=: read canary_approved canary_needs canary_failed <<< "$gate"
echo "QC canary gate approved=$canary_approved needs_review=$canary_needs failed=$canary_failed required_approved=10"
if test "$canary_approved" -lt 10; then
  echo "QC canary gate failed; remainder intentionally not started; inspect saved per-cluster results"
  exit 3
fi

tmux has-session -t municipal-qc-generic-remainder-review-v1 2>/dev/null && { echo "QC remainder reviewer exists"; exit 1; }
tmux new-session -d -s municipal-qc-generic-remainder-review-v1 -c "$PWD" "set -o pipefail; PGHOST=127.0.0.1 PGPORT=55434 PGUSER=brendansamek MUNICIPAL_FINANCIAL_OCR_CACHE_ROOT=$ocr_cache_root MUNICIPAL_FINANCIAL_OCR_CONCURRENCY=1 bin/rails runner script/review_extracted_municipal_financial_statements.rb --release 2026-08-27 --provinces qc --batch-size 25 --watch --idle-rounds 25920 2>&1 | tee $output_root/qc-generic-fallback-remainder-review-watch-v1-2026-08-30.jsonl"
MUNICIPAL_FINANCIAL_OCR_CONCURRENCY=2 bin/rails runner script/process_municipal_financial_statements.rb --release 2026-08-27 --province qc --rerun failed --failed-only --failed-parser quebec-mamh-form-v1 --exclude-document-ids "$canary_ids" 2>&1 | tee $output_root/qc-generic-fallback-remainder-v1-2026-08-30.jsonl
drain_qc municipal-qc-generic-remainder-review-v1
tmux kill-session -t municipal-qc-generic-remainder-review-v1 2>/dev/null || true
MUNICIPAL_FINANCIAL_OCR_CONCURRENCY=1 bin/rails runner script/review_extracted_municipal_financial_statements.rb --release 2026-08-27 --provinces qc --retry-needs-review --batch-size 25 2>&1 | tee $output_root/qc-generic-fallback-remainder-finite-review-v1-2026-08-30.jsonl
assert_terminal_checks
bin/rails runner 'release=Warehouse::InstitutionRelease.find_by!(version:"2026-08-27"); scope=release.financial_statement_extractions.where("institution_canonical_id LIKE ?","ca/qc/%").where(extractor_version:Warehouse::FinancialStatementExtraction::DetailedPipeline::EXTRACTOR_VERSION); active=scope.where(status:%w[pending extracting extracted]).count; abort "QC undrained detailed rows: #{active}" unless active.zero?; puts({qc_detailed_pending_extracting_extracted:0}.to_json)'
bin/rails runner script/audit_municipal_financial_extraction_coverage.rb --release 2026-08-27 --provinces qc --output $output_root/qc-generic-fallback-final-coverage-v1-2026-08-30.json
echo "QC generic fallback canary and gated remainder complete"
