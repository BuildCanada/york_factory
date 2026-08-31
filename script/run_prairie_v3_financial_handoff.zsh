#!/bin/zsh

set -e
set -o pipefail

cd "${0:A:h}/.."

output_root=/Volumes/floppy/york_factory/public_institutions/financial-extractions
ocr_cache_root=$output_root/ocr-cache-v1
coordinator_log=$output_root/prairie-v3-after-stable-v3-2026-08-30.log
ab_required_generic_success_percent=20
outputs=(
  $output_root/ab-prairie-v3-2026-08-30.jsonl
  $output_root/sk-prairie-v3-2026-08-30.jsonl
  $output_root/ab-prairie-v3-review-2026-08-30.jsonl
  $output_root/sk-prairie-v3-review-2026-08-30.jsonl
  $output_root/ab-prairie-generic-v1-2026-08-30.jsonl
  $output_root/ab-prairie-generic-review-v1-2026-08-30.jsonl
  $output_root/ab-prairie-generic-finite-review-v1-2026-08-30.jsonl
  $output_root/sk-prairie-generic-v1-2026-08-30.jsonl
  $output_root/sk-prairie-generic-review-v1-2026-08-30.jsonl
  $output_root/sk-prairie-generic-finite-review-v1-2026-08-30.jsonl
  $output_root/ab-prairie-v3-final-coverage-2026-08-30.json
  $output_root/sk-prairie-v3-final-coverage-2026-08-30.json
)

test ! -e "$coordinator_log"
for output_path in $outputs; do
  test ! -e "$output_path" || { echo "refusing existing output: $output_path"; exit 1; }
done
exec > >(tee "$coordinator_log") 2>&1
export PGHOST=127.0.0.1 PGPORT=55434 PGUSER=brendansamek MUNICIPAL_FINANCIAL_OCR_CACHE_ROOT=$ocr_cache_root MUNICIPAL_FINANCIAL_DETAIL_FLOW_CONCURRENCY=2

while kill -0 65389 2>/dev/null || kill -0 65392 2>/dev/null; do
  sleep 30
done

pane_alive() {
  tmux list-panes -t "$1" -F '#{pane_dead}' 2>/dev/null | rg -qx '0'
}

drain_parser() {
  province="$1"
  parser="$2"
  reviewer_session="$3"
  polls=0
  while true; do
    state=$(bin/rails runner "release=Warehouse::InstitutionRelease.find_by!(version:'2026-08-27'); scope=release.financial_statement_extractions.where('institution_canonical_id LIKE ?', 'ca/${province}/%').where(extractor_version:Warehouse::FinancialStatementExtraction::DetailedPipeline::EXTRACTOR_VERSION); active=scope.where(status:%w[pending extracting]).count; extracted=scope.where(status:'extracted').where(\"llm_response_snapshot ->> 'parser' = ?\", '${parser}').count; puts \"#{active}:#{extracted}\"" | tail -n 1)
    active="${state%%:*}"
    extracted="${state##*:}"
    test "$active" = "0" || { echo "$province active rows after extractor: $active"; exit 1; }
    if test "$extracted" = "0"; then
      echo "$province $parser reviewer drain complete"
      return
    fi
    pane_alive "$reviewer_session" || { echo "$reviewer_session died with $extracted extracted rows"; exit 1; }
    polls=$((polls + 1))
    test "$polls" -lt 720 || { echo "$province $parser reviewer drain timed out with $extracted rows"; exit 1; }
    echo "$province waiting for $parser reviewer: $extracted extracted rows"
    sleep 30
  done
}

assert_terminal_checks() {
  bin/rails runner 'terminal=%w[extracted needs_review approved rejected failed]; bad=Warehouse::FinancialStatementExtraction.where(status:terminal).where("jsonb_typeof(check_results) <> ? OR jsonb_array_length(check_results)=0","array").count; abort "terminal rows without checks: #{bad}" unless bad.zero?; puts({terminal_without_checks:0}.to_json)'
}

cleanup_generic_reviewers() {
  tmux kill-session -t municipal-ab-prairie-generic-review-v1 2>/dev/null || true
  tmux kill-session -t municipal-sk-prairie-generic-review-v1 2>/dev/null || true
}
trap cleanup_generic_reviewers EXIT INT TERM

generic_preflight() {
  province="$1"
  PROVINCE="$province" REQUIRED_PERCENT="$ab_required_generic_success_percent" bin/rails runner '
    province = ENV.fetch("PROVINCE")
    release = Warehouse::InstitutionRelease.find_by!(version: "2026-08-27")
    version = Warehouse::FinancialStatementExtraction::DetailedPipeline::EXTRACTOR_VERSION
    scope = release.financial_statement_extractions.where(
      "institution_canonical_id LIKE ?", "ca/#{province}/%"
    ).where(extractor_version: version)
    active = scope.where(status: %w[pending extracting extracted]).count
    abort "#{province.upcase} active rows before generic retry: #{active}" unless active.zero?
    allowed_parsers = %w[prairie-municipal-form-v2 prairie-municipal-form-v3]
    foreign = scope.where(status: "failed").filter_map do |row|
      parser = row.llm_response_snapshot&.fetch("parser", nil)
      [row.id, parser] unless allowed_parsers.include?(parser)
    end
    abort "#{province.upcase} non-prairie failed rows: #{foreign.take(10).inspect}" if foreign.any?
    candidates = Warehouse::FinancialStatementExtraction::CandidateSet.new(
      release:, provinces: [province]
    ).each.to_a
    report = Warehouse::FinancialStatementExtraction::FailedCandidateFilter.new(
      release:, province:, candidates:
    ).report
    abort "#{province.upcase} failed filter is not reconciled: #{report.slice(:unmatched_failure_count, :reconciled).inspect}" unless
      report.fetch(:unmatched_failure_count).zero? && report.fetch(:reconciled)
    totals = Warehouse::FinancialStatementExtraction::CoverageAudit.new(
      release:, provinces: [province]
    ).payload.fetch(:totals)
    baseline = totals.fetch(:published_institution_year_count)
    selected = report.fetch(:public_slot_count)
    percent = Integer(ENV.fetch("REQUIRED_PERCENT"))
    threshold = (selected * percent + 99) / 100
    puts [baseline, selected, threshold].join(":")
  ' | tail -n 1
}

drain_generic() {
  province="$1"
  reviewer_session="$2"
  polls=0
  while true; do
    state=$(bin/rails runner "release=Warehouse::InstitutionRelease.find_by!(version:'2026-08-27'); scope=release.financial_statement_extractions.where('institution_canonical_id LIKE ?', 'ca/${province}/%').where(extractor_version:Warehouse::FinancialStatementExtraction::DetailedPipeline::EXTRACTOR_VERSION); active=scope.where(status:%w[pending extracting]).count; extracted=scope.where(status:'extracted').count; puts \"#{active}:#{extracted}\"" | tail -n 1)
    active="${state%%:*}"
    extracted="${state##*:}"
    test "$active" = "0" || { echo "$province active rows after generic extractor: $active"; exit 1; }
    if test "$extracted" = "0"; then
      echo "$province generic reviewer drain complete"
      return
    fi
    pane_alive "$reviewer_session" || { echo "$reviewer_session died with $extracted extracted rows"; exit 1; }
    polls=$((polls + 1))
    test "$polls" -lt 1440 || { echo "$province generic reviewer drain timed out with $extracted rows"; exit 1; }
    echo "$province waiting for generic reviewer: $extracted extracted rows"
    sleep 30
  done
}

run_generic() {
  province="$1"
  reviewer_session="municipal-${province}-prairie-generic-review-v1"
  extraction_log="$output_root/${province}-prairie-generic-v1-2026-08-30.jsonl"
  reviewer_log="$output_root/${province}-prairie-generic-review-v1-2026-08-30.jsonl"
  finite_log="$output_root/${province}-prairie-generic-finite-review-v1-2026-08-30.jsonl"

  tmux has-session -t "$reviewer_session" 2>/dev/null && { echo "$reviewer_session already exists"; exit 1; }
  tmux new-session -d -s "$reviewer_session" -c "$PWD" "set -o pipefail; PGHOST=127.0.0.1 PGPORT=55434 PGUSER=brendansamek MUNICIPAL_FINANCIAL_OCR_CACHE_ROOT=$ocr_cache_root MUNICIPAL_FINANCIAL_OCR_CONCURRENCY=1 bin/rails runner script/review_extracted_municipal_financial_statements.rb --release 2026-08-27 --provinces $province --batch-size 25 --watch --idle-rounds 25920 2>&1 | tee $reviewer_log"
  MUNICIPAL_FINANCIAL_OCR_CONCURRENCY=2 bin/rails runner script/process_municipal_financial_statements.rb \
    --release 2026-08-27 --province "$province" --rerun failed --failed-only \
    2>&1 | tee "$extraction_log"
  drain_generic "$province" "$reviewer_session"
  tmux kill-session -t "$reviewer_session" 2>/dev/null || true
  MUNICIPAL_FINANCIAL_OCR_CONCURRENCY=1 bin/rails runner \
    script/review_extracted_municipal_financial_statements.rb \
    --release 2026-08-27 --provinces "$province" --retry-needs-review --batch-size 25 \
    2>&1 | tee "$finite_log"
  assert_terminal_checks
}

drain_parser ab prairie-municipal-form-v2 municipal-ab-stable-review
drain_parser sk prairie-municipal-form-v2 municipal-sk-stable-review
assert_terminal_checks
tmux kill-session -t municipal-ab-stable-review 2>/dev/null || true
tmux kill-session -t municipal-sk-stable-review 2>/dev/null || true

for session in municipal-ab-prairie-v3-review municipal-sk-prairie-v3-review municipal-ab-prairie-v3 municipal-sk-prairie-v3; do
  tmux has-session -t "$session" 2>/dev/null && { echo "$session already exists"; exit 1; }
done

tmux new-session -d -s municipal-ab-prairie-v3-review -c "$PWD" "set -o pipefail; PGHOST=127.0.0.1 PGPORT=55434 PGUSER=brendansamek MUNICIPAL_FINANCIAL_OCR_CACHE_ROOT=$ocr_cache_root MUNICIPAL_FINANCIAL_OCR_CONCURRENCY=1 ruby script/review_extracted_municipal_financial_statements.rb --release 2026-08-27 --provinces ab --parser-version prairie-municipal-form-v3 --batch-size 25 --watch --idle-rounds 25920 2>&1 | tee $output_root/ab-prairie-v3-review-2026-08-30.jsonl"
tmux new-session -d -s municipal-sk-prairie-v3-review -c "$PWD" "set -o pipefail; PGHOST=127.0.0.1 PGPORT=55434 PGUSER=brendansamek MUNICIPAL_FINANCIAL_OCR_CACHE_ROOT=$ocr_cache_root MUNICIPAL_FINANCIAL_OCR_CONCURRENCY=1 ruby script/review_extracted_municipal_financial_statements.rb --release 2026-08-27 --provinces sk --parser-version prairie-municipal-form-v3 --batch-size 25 --watch --idle-rounds 25920 2>&1 | tee $output_root/sk-prairie-v3-review-2026-08-30.jsonl"
tmux new-session -d -s municipal-ab-prairie-v3 -c "$PWD" "set -o pipefail; PGHOST=127.0.0.1 PGPORT=55434 PGUSER=brendansamek MUNICIPAL_FINANCIAL_OCR_CACHE_ROOT=$ocr_cache_root ruby script/process_saskatchewan_financial_forms.rb --release 2026-08-27 --province ab --failed-only 2>&1 | tee $output_root/ab-prairie-v3-2026-08-30.jsonl"
tmux set-option -t municipal-ab-prairie-v3 remain-on-exit on
tmux new-session -d -s municipal-sk-prairie-v3 -c "$PWD" "set -o pipefail; PGHOST=127.0.0.1 PGPORT=55434 PGUSER=brendansamek MUNICIPAL_FINANCIAL_OCR_CACHE_ROOT=$ocr_cache_root ruby script/process_saskatchewan_financial_forms.rb --release 2026-08-27 --province sk --failed-only 2>&1 | tee $output_root/sk-prairie-v3-2026-08-30.jsonl"
tmux set-option -t municipal-sk-prairie-v3 remain-on-exit on

polls=0
while true; do
  all_dead=1
  for session in municipal-ab-prairie-v3 municipal-sk-prairie-v3; do
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
  test "$polls" -lt 4320 || { echo "prairie v3 extractors timed out"; exit 1; }
  sleep 30
done

drain_parser ab prairie-municipal-form-v3 municipal-ab-prairie-v3-review
drain_parser sk prairie-municipal-form-v3 municipal-sk-prairie-v3-review
assert_terminal_checks
tmux kill-session -t municipal-ab-prairie-v3-review 2>/dev/null || true
tmux kill-session -t municipal-sk-prairie-v3-review 2>/dev/null || true

ab_gate=$(generic_preflight ab)
IFS=: read ab_baseline ab_selected ab_threshold <<< "$ab_gate"
echo "AB generic preflight baseline_published=$ab_baseline selected=$ab_selected required_delta=$ab_threshold percent=$ab_required_generic_success_percent"
run_generic ab
ab_published=$(bin/rails runner 'release=Warehouse::InstitutionRelease.find_by!(version:"2026-08-27"); totals=Warehouse::FinancialStatementExtraction::CoverageAudit.new(release:,provinces:["ab"]).payload.fetch(:totals); puts totals.fetch(:published_institution_year_count)' | tail -n 1)
ab_delta=$((ab_published - ab_baseline))
echo "AB generic gate published=$ab_published delta=$ab_delta required_delta=$ab_threshold selected=$ab_selected"
if test "$ab_delta" -lt "$ab_threshold"; then
  echo "AB generic gate failed; SK generic fallback intentionally not started"
  exit 3
fi

sk_gate=$(generic_preflight sk)
IFS=: read sk_baseline sk_selected sk_threshold <<< "$sk_gate"
echo "SK generic preflight baseline_published=$sk_baseline selected=$sk_selected informational_threshold=$sk_threshold"
run_generic sk

cleanup_generic_reviewers
trap - EXIT INT TERM
bin/rails runner script/audit_municipal_financial_extraction_coverage.rb --release 2026-08-27 --provinces ab --output $output_root/ab-prairie-v3-final-coverage-2026-08-30.json
bin/rails runner script/audit_municipal_financial_extraction_coverage.rb --release 2026-08-27 --provinces sk --output $output_root/sk-prairie-v3-final-coverage-2026-08-30.json
echo "Prairie deterministic and generic fallback handoff complete"
