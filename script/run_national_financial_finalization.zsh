#!/bin/zsh

set -e
set -o pipefail

cd "${0:A:h}/.."

output_root=/Volumes/floppy/york_factory/public_institutions/financial-extractions
ocr_cache_root=$output_root/ocr-cache-v1
run_stamp=2026-08-30
coordinator_log=$output_root/national-finalization-v1-$run_stamp.log
legacy_dry_run=$output_root/national-legacy-reviewer-dry-run-v1-$run_stamp.jsonl
legacy_promotion=$output_root/national-legacy-reviewer-promotion-v1-$run_stamp.jsonl
coverage_output=$output_root/national-final-per-record-verification-v1-$run_stamp.json
york_test_log=$output_root/national-final-york-tests-v1-$run_stamp.log
york_quality_log=$output_root/national-final-york-quality-v1-$run_stamp.log
frontend_test_log=$output_root/national-final-canadaspends-tests-v1-$run_stamp.log
frontend_build_log=$output_root/national-final-canadaspends-build-v1-$run_stamp.log
local_api_result=$output_root/national-final-local-toronto-api-v1-$run_stamp.json
local_frontend_result=$output_root/national-final-local-toronto-page-v1-$run_stamp.html
local_redirect_headers=$output_root/national-final-local-toronto-redirect-v1-$run_stamp.headers
tunnel_frontend_result=$output_root/national-final-tunnel-toronto-page-v1-$run_stamp.html
tunnel_redirect_headers=$output_root/national-final-tunnel-toronto-redirect-v1-$run_stamp.headers
transient_retry_provinces=(nl mb nb pe on)
transient_retry_logs=()
for retry_province in $transient_retry_provinces; do
  transient_retry_logs+=(
    $output_root/$retry_province-national-headline-retry-v1-$run_stamp.jsonl
    $output_root/$retry_province-national-detailed-retry-v1-$run_stamp.jsonl
    $output_root/$retry_province-national-retry-review-v1-$run_stamp.jsonl
  )
done

outputs=(
  $coordinator_log $legacy_dry_run $legacy_promotion $coverage_output
  $york_test_log $york_quality_log $frontend_test_log $frontend_build_log
  $local_api_result $local_frontend_result $local_redirect_headers
  $tunnel_frontend_result $tunnel_redirect_headers
  $transient_retry_logs
)
for output_path in $outputs; do
  test ! -e "$output_path" || { echo "refusing existing output: $output_path"; exit 1; }
done
exec > >(tee "$coordinator_log") 2>&1
export PGHOST=127.0.0.1 PGPORT=55434 PGUSER=brendansamek MUNICIPAL_FINANCIAL_OCR_CACHE_ROOT=$ocr_cache_root

dependencies=(
  municipal-territories-after-nl-v1
  municipal-atlantic-nb-pe-after-mb-v2
  municipal-ns-bc-after-atlantic-v2
  municipal-on-final-after-bounded-lanes-v2
  municipal-qc-generic-fallback-after-on-v1
  municipal-prairie-v3-after-stable-v3
)

polls=0
while true; do
  all_dead=1
  for session in $dependencies; do
    dead=$(tmux display-message -p -t "$session":0 '#{pane_dead}' 2>/dev/null) || {
      echo "$session disappeared"
      exit 1
    }
    if test "$dead" = "1"; then
      exit_status=$(tmux display-message -p -t "$session":0 '#{pane_dead_status}')
      test "$exit_status" = "0" || {
        echo "$session failed with status $exit_status; finalization intentionally halted"
        exit 1
      }
    else
      all_dead=0
    fi
  done
  test "$all_dead" = "0" || break
  polls=$((polls + 1))
  test "$polls" -lt 40320 || { echo "national dependency wait timed out"; exit 1; }
  sleep 30
done
echo "All provincial and territorial coordinators completed cleanly"

# Generic-first provinces get one slot-guarded retry for both headline and detailed failures.
# Headline failures must be selected separately because they have no persisted detailed row.
for retry_province in $transient_retry_provinces; do
  headline_retry_log=$output_root/$retry_province-national-headline-retry-v1-$run_stamp.jsonl
  detailed_retry_log=$output_root/$retry_province-national-detailed-retry-v1-$run_stamp.jsonl
  retry_review_log=$output_root/$retry_province-national-retry-review-v1-$run_stamp.jsonl

  MUNICIPAL_FINANCIAL_OCR_CONCURRENCY=2 MUNICIPAL_FINANCIAL_DETAIL_FLOW_CONCURRENCY=2 \
    bin/rails runner script/process_municipal_financial_statements.rb \
      --release 2026-08-27 --province "$retry_province" --rerun failed --failed-only \
      --failed-extractor headline 2>&1 | tee "$headline_retry_log"
  MUNICIPAL_FINANCIAL_OCR_CONCURRENCY=2 MUNICIPAL_FINANCIAL_DETAIL_FLOW_CONCURRENCY=2 \
    bin/rails runner script/process_municipal_financial_statements.rb \
      --release 2026-08-27 --province "$retry_province" --rerun failed --failed-only \
      --failed-extractor detailed 2>&1 | tee "$detailed_retry_log"
  MUNICIPAL_FINANCIAL_OCR_CONCURRENCY=1 \
    bin/rails runner script/review_extracted_municipal_financial_statements.rb \
      --release 2026-08-27 --provinces "$retry_province" --batch-size 25 \
      2>&1 | tee "$retry_review_log"

  PROVINCE="$retry_province" bin/rails runner '
    release = Warehouse::InstitutionRelease.find_by!(version: "2026-08-27")
    province = ENV.fetch("PROVINCE")
    scope = release.financial_statement_extractions.where(
      "institution_canonical_id LIKE ?", "ca/#{province}/%"
    )
    detailed = scope.where(
      extractor_version: Warehouse::FinancialStatementExtraction::DetailedPipeline::EXTRACTOR_VERSION
    )
    headline = scope.where(
      extractor_version: Warehouse::FinancialStatementExtraction::Pipeline::EXTRACTOR_VERSION
    )
    detailed_active = detailed.where(status: %w[pending extracting extracted]).count
    headline_active = headline.where(status: %w[pending extracting]).count
    terminal = %w[extracted needs_review approved rejected failed]
    without_checks = Warehouse::FinancialStatementExtraction.where(status: terminal)
      .where("jsonb_typeof(check_results) <> ? OR jsonb_array_length(check_results)=0", "array").count
    abort "#{province.upcase} detailed rows undrained after retry: #{detailed_active}" unless detailed_active.zero?
    abort "#{province.upcase} headline rows active after retry: #{headline_active}" unless headline_active.zero?
    abort "terminal rows without checks after #{province.upcase} retry: #{without_checks}" unless without_checks.zero?
    puts({ province:, detailed_active: 0, headline_active: 0, terminal_without_checks: 0 }.to_json)
  '
done
echo "Generic-first provincial headline and detailed retry sweep completed"

# Review watchers are no longer allowed to mutate data once the extraction lanes have drained.
reviewer_sessions=(
  municipal-mb-review-watch-v1 municipal-nb-review-watch-v1 municipal-pe-review-watch-v1
  municipal-on-review-shard0-v1 municipal-on-review-shard1-v1
  municipal-sk-stable-review municipal-ab-stable-review
  municipal-ab-prairie-v3-review municipal-sk-prairie-v3-review
  municipal-bc-stable-review municipal-nl-retry-review-after-v2
  municipal-qc-generic-canary-review-v1 municipal-qc-generic-remainder-review-v1
)
for session in $reviewer_sessions; do
  tmux kill-session -t "$session" 2>/dev/null || true
done

if pgrep -fl 'process_(municipal_financial_statements|quebec_financial_forms|saskatchewan_financial_forms)\.rb' > /tmp/national-financial-extraction-processes.txt; then
  cat /tmp/national-financial-extraction-processes.txt
  echo "extraction process still running; frozen finalization halted"
  exit 1
fi

preflight=$(bin/rails runner 'release=Warehouse::InstitutionRelease.find_by!(version:"2026-08-27"); version=Warehouse::FinancialStatementExtraction::DetailedPipeline::EXTRACTOR_VERSION; release_scope=release.financial_statement_extractions; detailed=release_scope.where(extractor_version:version); active=detailed.where(status:%w[pending extracting extracted]).count; bad_terminal=Warehouse::FinancialStatementExtraction.where(status:%w[extracted needs_review approved rejected failed]).where("jsonb_typeof(check_results) <> ? OR jsonb_array_length(check_results)=0","array").count; deterministic=Warehouse::FinancialStatementExtraction::Reviewer::DETERMINISTIC_REVIEWERS; legacy=detailed.where(status:"approved").where("reviewed_by IS NULL OR reviewed_by NOT IN (?)",deterministic).group(:reviewed_by).count; abort "national active detailed rows: #{active}" unless active.zero?; abort "terminal rows without checks: #{bad_terminal}" unless bad_terminal.zero?; abort "unexpected legacy reviewers: #{legacy.inspect}" unless (legacy.keys.compact-["local-detailed-validator"]).empty? && !legacy.key?(nil); puts({active_detailed:0,terminal_without_checks:0,legacy_reviewers:legacy}.to_json)' | tail -n 1)
echo "$preflight"
legacy_count=$(echo "$preflight" | ruby -rjson -e 'puts JSON.parse(STDIN.read).fetch("legacy_reviewers").fetch("local-detailed-validator",0)')

bin/rails runner script/review_extracted_municipal_financial_statements.rb \
  --release 2026-08-27 --audit-approved-by local-detailed-validator --dry-run \
  2>&1 | tee "$legacy_dry_run"
dry_count=$(tail -n 1 "$legacy_dry_run" | ruby -rjson -e 'puts JSON.parse(STDIN.read).fetch("reviewed")')
test "$dry_count" = "$legacy_count" || {
  echo "legacy dry-run count drift: expected=$legacy_count actual=$dry_count"
  exit 1
}

if test "$legacy_count" -gt 0; then
  bin/rails runner script/review_extracted_municipal_financial_statements.rb \
    --release 2026-08-27 --promote-audit-approved-by local-detailed-validator \
    2>&1 | tee "$legacy_promotion"
else
  echo '{"release":"2026-08-27","promote_audit":true,"reviewed":0,"promoted":0}' | tee "$legacy_promotion"
fi
promotion_summary=$(tail -n 1 "$legacy_promotion")
promoted=$(echo "$promotion_summary" | ruby -rjson -e 'puts JSON.parse(STDIN.read).fetch("promoted")')
reviewed=$(echo "$promotion_summary" | ruby -rjson -e 'puts JSON.parse(STDIN.read).fetch("reviewed")')
test "$reviewed" = "$legacy_count" && test "$promoted" = "$legacy_count" || {
  echo "legacy promotion incomplete: expected=$legacy_count reviewed=$reviewed promoted=$promoted"
  exit 1
}

bin/rails runner script/audit_municipal_financial_extraction_coverage.rb \
  --release 2026-08-27 --output "$coverage_output"
COVERAGE_OUTPUT="$coverage_output" bin/rails runner 'payload=JSON.parse(File.read(ENV.fetch("COVERAGE_OUTPUT"))); totals=payload.fetch("totals"); statuses=totals.fetch("status_counts"); forbidden=%w[unattempted pending extracting extracted headline_pending headline_extracting headline_extracted]; present=forbidden.to_h { [_1,statuses.fetch(_1,0)] }.reject { |_key,value| value.zero? }; gates={approved_without_checks:totals.fetch("approved_without_checks"),failed_headline_gate_without_checks:totals.fetch("failed_headline_gate_without_checks"),shared_asset_with_terminal_extraction_without_checks:totals.fetch("shared_asset_with_terminal_extraction_without_checks"),approved_without_deterministic_reviewer:totals.fetch("approved_without_deterministic_reviewer")}; abort "unresolved coverage statuses: #{present.inspect}" if present.any?; abort "coverage verification gates failed: #{gates.inspect}" unless gates.values.all?(&:zero?); records=payload.fetch("records"); missing=records.select { |row| row.fetch("status")!="shared_asset" && row.dig("verification","total").to_i.zero? && row.fetch("status").in?(%w[approved rejected failed needs_review failed_headline_gate]) }; abort "terminal coverage records without saved results: #{missing.take(10).map { _1.fetch("document_canonical_id") }.inspect}" if missing.any?; puts({preferred_assets:totals.fetch("preferred_asset_count"),institution_years:totals.fetch("institution_year_count"),published_institution_years:totals.fetch("published_institution_year_count"),status_counts:statuses,verification_gates:gates}.to_json)'

{
  bundle exec ruby test/scripts/sanitize_municipal_report_batch_test.rb
  bin/rails test \
    test/controllers/api/v1/warehouse/municipal_financial_statements_controller_test.rb \
    test/jobs/warehouse/extract_municipal_financial_statements_job_test.rb \
    test/models/warehouse/census_profile_importer_test.rb \
    test/models/warehouse/financial_statement_extraction_test.rb \
    test/models/warehouse/financial_statement_extraction/*.rb \
    test/scripts/audit_municipal_financial_extraction_coverage_test.rb
} 2>&1 | tee "$york_test_log"

{
  bundle exec rubocop \
    app/controllers/api/v1/warehouse/municipal_financial_statements_controller.rb \
    app/jobs/warehouse/extract_municipal_financial_statements_job.rb \
    app/models/warehouse/financial_statement_extraction.rb \
    app/models/warehouse/financial_statement_extraction \
    app/models/warehouse/financial_statement_line_item.rb \
    app/models/warehouse/census_profile.rb app/models/warehouse/census_profile_importer.rb \
    script/audit_municipal_financial_extraction_coverage.rb \
    script/process_municipal_financial_statements.rb \
    script/review_extracted_municipal_financial_statements.rb \
    script/sanitize_municipal_report_batch.rb \
    test/scripts/sanitize_municipal_report_batch_test.rb
  bin/rails zeitwerk:check
} 2>&1 | tee "$york_quality_log"

(
  cd ../CanadaSpends
  pnpm test 2>&1 | tee "$frontend_test_log"
  YORK_FACTORY_API_URL=http://127.0.0.1:3001/api/v1 pnpm build \
    2>&1 | tee "$frontend_build_log"
)

curl --fail --silent --show-error \
  http://127.0.0.1:3001/api/v1/warehouse/municipal_financial_statements/on/toronto/2025 \
  -o "$local_api_result"
API_RESULT="$local_api_result" ruby -rjson -e 'payload=JSON.parse(File.read(ENV.fetch("API_RESULT"))); statement=payload.fetch("statements").find { _1.fetch("fiscal_year")==2025 } or abort "Toronto 2025 absent"; verification=statement.fetch("verification"); abort "saved checks absent" unless verification.dig("summary","total").to_i.positive? && verification.fetch("checks").any?; sankey=statement.fetch("sankey"); revenue_children=sankey.dig("revenue_data","children"); spending_children=sankey.dig("spending_data","children"); abort "Sankey absent" unless sankey.fetch("revenue").positive? && sankey.fetch("spending").positive? && revenue_children&.any? && spending_children&.any?; abort "context absent" unless payload.dig("context","population").to_i.positive?; puts({toronto_latest:payload.fetch("available_years").max,checks:verification.dig("summary","total"),sankey_revenue_groups:revenue_children.length,sankey_spending_groups:spending_children.length,population:payload.dig("context","population")}.to_json)'

curl --fail --silent --show-error --head \
  --dump-header "$local_redirect_headers" --output /dev/null \
  http://127.0.0.1:3200/en/municipal/on/toronto
rg -q '^HTTP/[^ ]+ 307' "$local_redirect_headers"
rg -qi '^location: /en/municipal/on/toronto/2025\r?$' "$local_redirect_headers"

curl --fail --silent --show-error http://127.0.0.1:3200/en/municipal/on/toronto/2025 \
  -o "$local_frontend_result"
rg -q 'View all [0-9]+ verification checks' "$local_frontend_result"
rg -q 'Inflows|Outflows' "$local_frontend_result"

tunnel_session=$(tmux list-sessions -F '#{session_name}' | rg '^municipal-cloudflare-tunnel' | tail -n 1)
test -n "$tunnel_session" || { echo "Cloudflare tunnel session not found"; exit 1; }
tunnel_log=/tmp/$tunnel_session.log
tunnel_url=$({
  tmux capture-pane -pt "$tunnel_session" -S -
  test ! -f "$tunnel_log" || sed -n '1,240p' "$tunnel_log"
} | rg -o 'https://[a-z0-9-]+\.trycloudflare\.com' | tail -n 1)
test -n "$tunnel_url" || { echo "Cloudflare tunnel URL not found"; exit 1; }
curl --fail --silent --show-error --head \
  --dump-header "$tunnel_redirect_headers" --output /dev/null \
  "$tunnel_url/en/municipal/on/toronto"
rg -q '^HTTP/[^ ]+ 307' "$tunnel_redirect_headers"
rg -qi '^location: /en/municipal/on/toronto/2025\r?$' "$tunnel_redirect_headers"

curl --fail --silent --show-error "$tunnel_url/en/municipal/on/toronto/2025" \
  -o "$tunnel_frontend_result"
rg -q 'View all [0-9]+ verification checks' "$tunnel_frontend_result"
rg -q 'Inflows|Outflows' "$tunnel_frontend_result"

echo "National financial extraction finalization and local/tunnel QA complete: $tunnel_url"
