---
name: orchestrate-government-kpi-series
description: Orchestrate multi-year government KPI ingestion from an index/listing page by extracting all primary source report URLs, then launching year-by-year subagents that use the ingest-government-kpis skill on each report URL. Use when the user provides a Canada.ca or government report listing page, departmental results report index, departmental plan index, annual report archive, budget report archive, or any URL that contains multiple yearly KPI source documents.
---

# Orchestrate Government KPI Series

Expand one report-listing URL into one source-document URL per year, then run
`ingest-government-kpis` on each report sequentially. The single-report ingestion
skill must only receive a concrete report URL, never an index page.

This skill coordinates subagents. It should not directly extract KPI rows or POST
citations itself except for read-only discovery calls.

## Inputs

Required:

- `SOURCE_INDEX_URL`: an index/listing page containing multiple yearly source documents.

Optional:

- `JURISDICTION_SLUG`
- `ORG_SLUG`
- `ORG_NAME`
- year range, e.g. `2021-2025`
- document type preference, e.g. `departmental_results_report`,
  `departmental_plan`, `annual_report`, `budget`
- `DRY_RUN=true` to build and validate the manifest and subagent prompts without
  launching ingestion subagents or writing to the KPI API

If no year range is specified, ingest every primary report link discovered on
the listing page, oldest to newest.

## Hard Rules

- Extract the report manifest first. Do not start ingestion until the manifest is clear.
- Pass only concrete report URLs to `ingest-government-kpis`.
- Run subagents sequentially from oldest year to newest year so later agents can build on existing measures, compositions, and lineage decisions.
- After each subagent completes, summarize its results and pass that summary to the next subagent.
- If one year fails because of missing reference data or ambiguous source structure, stop the series unless the failure is explicitly scoped to that year and the next year can proceed safely. Unknown units are not a stop condition: the ingest subagent prefers existing units and creates genuinely new ones via `/admin/units`.
- Probe each report URL before launching its subagent. Skip unreachable legacy
  URLs only when they are outside the user-requested year range or when
  `SKIP_UNREACHABLE=true`; otherwise stop and report the first unreachable URL.
- Never ask a subagent to process the index URL directly.
- Do not run multiple year-ingestion subagents in parallel for the same organization and report family; that defeats measure/composition reuse.

## Preflight

Use the same API readiness checks as the ingestion skill:

```bash
API="${YORK_FACTORY_API_URL:-http://localhost:3000}"
TOKEN="${YORK_FACTORY_KPI_TOKEN:-$(cat ~/.config/york-factory/kpi-token 2>/dev/null)}"
test -n "$TOKEN" || { echo "Missing YORK_FACTORY_KPI_TOKEN"; exit 1; }
curl -sf "$API/up" >/dev/null || { echo "Start the Rails server: bin/rails server"; exit 1; }
```

## Build The Report Manifest

Fetch and parse the listing page:

```bash
curl -Ls "$SOURCE_INDEX_URL" \
  | ruby -r json -r nokogiri -r uri -e '
      base = URI(ARGV[0])
      html = Nokogiri::HTML($stdin.read)
      links = html.css("a[href]").map do |a|
        text = a.text.gsub(/\s+/, " ").strip
        url = URI.join(base, a["href"].to_s).to_s
        next if text.empty? || url == base.to_s
        [text, url]
      end.compact

      reject = /at a glance|operating context|framework|supplementary|financial statements|infographic|fees report|audited financial/i
      primary = /departmental results report|departmental result report|departmental performance report|departmental plan|annual report|business plan|service plan|operating budget/i
      year_re = /(20\d{2})(?:[\-–](\d{2,4}))?/

      docs = links.each_with_object([]) do |(text, url), out|
        next unless text.match?(primary) || url.match?(primary)
        next if text.match?(reject) || url.match?(reject)
        match = text.match(year_re) || url.match(year_re)
        next unless match
        start_year = match[1].to_i
        end_year = match[2]&.to_i
        fiscal_year = if end_year.nil?
          start_year
        elsif end_year < 100
          (start_year / 100) * 100 + end_year
        else
          end_year
        end
        out << { fiscal_year: fiscal_year, title: text, url: url }
      end

      docs.uniq { |doc| [doc[:fiscal_year], doc[:url]] }
          .sort_by { |doc| doc[:fiscal_year] }
          .each { |doc| puts JSON.generate(doc) }
    ' "$SOURCE_INDEX_URL"
```

Review the manifest before launching subagents:

- Confirm every row is a primary source report.
- Remove duplicates and non-primary documents.
- Apply the requested year range if provided.
- For current Canada federal reports, fiscal year `2024-25` means
  `fiscal_year: 2025`.

If the manifest is empty or ambiguous, stop and report the issue. Do not guess.

## Validate Report URLs

Probe manifest URLs before launching ingestion:

```bash
while read -r doc; do
  url=$(echo "$doc" | jq -r '.url')
  code=$(curl -ILs --max-time 20 -o /dev/null -w '%{http_code}' "$url" || true)
  echo "$doc" | jq --arg code "$code" '. + {http_status:$code}'
done < manifest.jsonl
```

Use this policy:

- `200`, `301`, `302`, and other normal redirect-final statuses are usable when
  the resolved body is a report page.
- `404`, `410`, `000`, request-blocked pages, and empty bodies are unreachable.
- If the user supplied a year range, unreachable reports inside that range are
  blockers.
- If no year range was supplied, skip unreachable legacy reports and include
  them in the final `skipped reports` list, then continue oldest-to-newest among
  reachable reports.
- For old `http://www.tbs-sct.gc.ca` links, try `https://www.tbs-sct.canada.ca`
  only as a probe. Use the URL that actually returns a report body.

## Dry Run Mode

When `DRY_RUN=true`:

- Build the manifest.
- Probe report URLs.
- Apply year range and reachability policy.
- Construct the first two subagent prompts and the final subagent prompt.
- Do not call admin write endpoints.
- Do not launch ingestion subagents.
- Return whether a real run is safe and exactly which years would run or skip.

## Discover Current Catalog Before First Year

If organization slug is known, read existing catalog state:

```bash
curl -s "$API/api/v1/kpis/measures?organization_slug=$ORG_SLUG&per_page=100" \
  | jq '.data[] | {id, slug, canonical_name, unit: .unit.symbol, service_category}'

curl -s "$API/api/v1/kpis/compositions?organization_slug=$ORG_SLUG&per_page=100" \
  | jq '.data[] | {measure_id: .measure.id, composition_id: .id, composition_type, name,
                   components: [.components[] | {id, component_type, component_code, component_name}]}'
```

Include this catalog summary in the first subagent prompt. For later subagents,
include the previous subagent summaries plus any newly created/reused measures
or composition decisions.

## Launch Year Subagents

For each manifest row in ascending `fiscal_year`, spawn one subagent with:

- the `ingest-government-kpis` skill item/path
- the concrete report URL as `DOC_URL`
- the listing URL as context only, not as the document URL
- fiscal year
- jurisdiction/org hints
- previous-year summary
- instruction not to edit repository files unless the ingestion skill explicitly
  requires seed/reference-data edits and the user has approved those edits

Subagent prompt template:

```text
Use the ingest-government-kpis skill at
/Users/brendansamek/dev/BuildCanada/york_factory/.agents/skills/ingest-government-kpis
to ingest KPIs from this single report URL:
<DOC_URL>

Work from /Users/brendansamek/dev/BuildCanada/york_factory.
This is fiscal year <FISCAL_YEAR>.
The source listing page is <SOURCE_INDEX_URL>; use it only as source_page_url/context.
Jurisdiction hint: <JURISDICTION_SLUG or unknown>.
Organization hint: <ORG_SLUG/ORG_NAME or unknown>.

Previous-year ingestion context:
<summary of prior subagent result, reused measures, new measures, composition decisions, created units, lineage candidates>

Do not process the listing URL directly. If this URL is not a single report,
stop and report that exact problem. Return a concise summary with agent_run_id,
document_id, counts, created/reused measures, composition/component decisions,
flags, created units, lineage candidates, and blockers.
```

Wait for the subagent to complete before starting the next year. If the result
shows missing reference data, stop and ask the user whether to fix reference
data before continuing. Created units are not a stop condition; pass them
forward in the next subagent's context so later years reuse them.

## Carry Forward State

After each year:

1. Record `fiscal_year`, `report_url`, `agent_run_id`, and `document_id`.
2. Record measures created, reused, renamed, split, merged, or likely replaced.
3. Record composition/component IDs used or newly detected.
4. Record flags and unresolved review issues.
5. Query the API catalog again if the subagent created or reused measures:

```bash
curl -s "$API/api/v1/kpis/measures?organization_slug=$ORG_SLUG&per_page=100" | jq '.data'
curl -s "$API/api/v1/kpis/compositions?organization_slug=$ORG_SLUG&per_page=100" | jq '.data'
```

Pass the updated state into the next subagent.

## Final Report

Return one series-level summary:

- source index URL
- report manifest processed
- skipped reports and why
- year-by-year subagent outcomes
- total documents, measures, citations inserted/skipped, flags, assertions, footnotes
- created units and unresolved reference data
- lineage candidates across years
- composition/component changes across years
- exact next action if the series stopped early
