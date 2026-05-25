---
name: toronto-budget-kpis
description: Extract Service Performance / KPI measures from City of Toronto budget-note PDFs for a given agency and fiscal year, and POST them to the York Factory admin API (warehouse.measure_citations). Every write is tagged with an agent_run row for traceability. Use when the user asks to extract, populate, or backfill Toronto KPIs into York Factory (e.g., "extract KPIs for TTC 2027", "populate Parks performance measures for 2026", "ingest EDC KPIs from the new budget note").
allowed-tools:
  - Bash
  - Read
  - AskUserQuestion
---

# Toronto budget KPI extractor → York Factory

Extracts the "Service Performance" / "Performance Measures" / "Key Service Levels" tables from a single Toronto agency budget-note PDF, posts the data to the York Factory admin API, and submits a markdown report attached to a `warehouse.agent_runs` row so the entire extraction is queryable later.

Replaces the old SQLite-targeting workflow at `~/.claude/skills/toronto-budget-kpis/` (which wrote Python scripts against `~/dev/toronto-budgets/scrape.db`). That data was bulk-loaded into York Factory once via `kpis:import_toronto_v1`; going forward, new extractions land here via HTTP.

## When to use

- "Extract Police KPIs for 2027"
- "Add Parks/Forestry/Recreation KPIs from the new budget note"
- "Backfill TTC performance measures for 2026"

One run = one agency × one fiscal-year PDF. If the user asks for multiple years, run the skill once per year and PATCH each run separately. Multiple agencies in one session: same — one run each, distinct `agent_runs` rows.

## Pre-flight

Before the first run, ensure two things are in place:

### 1. API token

Resolve in this order:
1. `$YORK_FACTORY_KPI_TOKEN` (env var)
2. `~/.config/york-factory/kpi-token` (file, chmod 600)

If neither exists, instruct the user:

```bash
cd ~/dev/BuildCanada/york_factory
bin/rails kpis:issue_token name=toronto-budget-kpis
# copy the printed token (it starts with yfk_), then:
mkdir -p ~/.config/york-factory
echo 'yfk_...' > ~/.config/york-factory/kpi-token
chmod 600 ~/.config/york-factory/kpi-token
```

### 2. API base URL

`$YORK_FACTORY_API_URL`, default `http://localhost:3000`. The skill expects the Rails server to be running. If `curl -sf $YORK_FACTORY_API_URL/up` fails, ask the user to start it (`bin/rails server` from the york_factory repo) before proceeding.

### Skill setup snippet

Run this once at the start of every invocation:

```bash
TOKEN="${YORK_FACTORY_KPI_TOKEN:-$(cat ~/.config/york-factory/kpi-token 2>/dev/null)}"
[ -z "$TOKEN" ] && { echo "no token — see pre-flight in SKILL.md"; exit 1; }
API="${YORK_FACTORY_API_URL:-http://localhost:3000}"
AUTH="-H \"Authorization: Bearer $TOKEN\" -H \"Content-Type: application/json\""
curl -sf "$API/up" >/dev/null || { echo "$API not reachable — start \`bin/rails server\`"; exit 1; }
```

## Workflow

### Step 1 — Confirm canonical organization

Look up the organization in York Factory. The string the user gives (e.g. "EDC", "Parks") may match several aliases.

```bash
curl -s "$API/api/v1/kpis/jurisdictions/toronto/organizations" \
  | jq '.data[] | select(.canonical_name | test("'"$AGENCY_TERM"'"; "i")) | {slug, canonical_name, active_from_year, active_to_year}'
```

If exactly one row matches, use its `slug`. If multiple, show them to the user and ask which. If none match, the agency is probably under an alias — show all 53 and let the user pick.

Store the chosen `slug` as `ORG_SLUG`.

### Step 2 — Open an agent run

```bash
RUN=$(curl -s -X POST "$API/api/v1/kpis/admin/agent_runs" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d "$(jq -n --arg org "$ORG_SLUG" --argjson yr $FISCAL_YEAR \
       '{agent_run: {agent_name:"toronto-budget-kpis",
                     agent_version:"'"$(cd ~/dev/BuildCanada/york_factory && git rev-parse --short HEAD)"'",
                     input_params:{organization_slug:$org, fiscal_year:$yr}}}')")
RUN_ID=$(echo "$RUN" | jq .id)
```

If `RUN_ID` is null, abort and report the response. Every subsequent call passes `agent_run_id: $RUN_ID` so the writes are traceable.

### Step 3 — Register the PDF document

The user gives you a PDF URL or a local file path. Decide the canonical `doc_url`:
- If the PDF was downloaded from `toronto.ca/budget` or similar, use that URL.
- If only local, ask the user for the source URL. Don't invent one.

```bash
DOC=$(curl -s -X POST "$API/api/v1/kpis/admin/documents" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d "$(jq -n \
        --arg org "$ORG_SLUG" --argjson yr $FISCAL_YEAR \
        --arg url "$DOC_URL" --arg title "$DOC_TITLE" \
        --argjson rid $RUN_ID \
        '{document: {jurisdiction_slug:"toronto", organization_slug:$org,
                     fiscal_year:$yr, doc_url:$url, doc_title:$title,
                     agent_run_id:$rid}}')")
DOC_ID=$(echo "$DOC" | jq .id)
```

Idempotent on `doc_url`: posting the same URL twice returns the same `id`.

### Step 4 — Read the PDF

Use the `Read` tool with the `pages:` argument. **Don't load the whole PDF.**

1. Read pages 1–3 to get the table of contents / overview.
2. Look for headings: "Service Performance", "Performance Measures", "Key Service Levels", "Key Performance Indicators", "Outcomes".
3. Jump to those pages (typically 4–6 for 2019+ notes; spread across 15–30 for 2017–2018 multi-service notes).

For each measure row, capture:
- `canonical_name` — wording exactly as it appears in the PDF heading.
- `unit_symbol` — must already exist in `warehouse.units`. Common symbols: `#`, `%`, `$`, `$M`, `$B`, `count`, `count_thousands`, `seconds`, `hours`, `business_days`, `score`, `index`, `rating`, `pass/fail`, `text`, `date`. Full list: `curl -s "$API/api/v1/kpis/jurisdictions/toronto/organizations" >/dev/null; psql ... SELECT symbol FROM warehouse.units` — or just try the POST; if the symbol is unknown, the API returns 422 with `error: "unknown_unit"`.
- `service_category` — the section heading the measure sits under.
- For each year column: a measurement_year, value_type, value_numeric (or value_text for qualitative), page_number, and notes for anything unusual.

**`value_type` rules:**
- Historical years (before the budget year): `actual`
- Budget year: `budget` (labeled "Budget"), `target` ("Target"), `plan` ("Plan"), `projected` ("Projected")
- Future plan years: `plan` or `projected` per labeling
- The same (measure, measurement_year, value_type) reported in multiple budget docs is a *feature* — each insert has its own `document_id` (unique constraint already permits it), and `measure_facts` resolves to the latest published doc. This is how the system tracks target restatements.

**Critical conventions:**
- **`page_number` = physical PDF page index (1-based)** as the `Read` tool numbers them. NOT printed page numbers.
- **Don't fabricate.** If a cell is unreadable, skip it; record the gap in the report.
- **Methodology shift = separate measure**, not the same. e.g., if a 2026 doc replaces "Jobs Created and Retained" with "Businesses Provided with Material Support", create two distinct measures. Capture the relationship via `POST /api/v1/kpis/admin/measure_lineages` later if known.
- **Minor name variant = same measure.** "Film Production Spending" → "Film and Television Production Spending" is the same — keep one canonical_name.

### Step 5 — Upsert measures

For each unique measure in the table:

```bash
M=$(curl -s -X POST "$API/api/v1/kpis/admin/measures" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d "$(jq -n \
        --arg org "$ORG_SLUG" --arg slug "$MEASURE_SLUG" \
        --arg name "$CANONICAL_NAME" --arg unit "$UNIT_SYMBOL" \
        --arg cat "$SERVICE_CATEGORY" --argjson yr $FISCAL_YEAR \
        --argjson rid $RUN_ID \
        '{measure: {organization_slug:$org, slug:$slug, canonical_name:$name,
                    unit_symbol:$unit, service_category:$cat,
                    last_seen_year:$yr, agent_run_id:$rid}}')")
MEASURE_ID=$(echo "$M" | jq .id)
```

`MEASURE_SLUG` is the canonical_name parameterized: lowercase ASCII, non-alphanumerics → hyphens, strip leading/trailing hyphens.

If response status is 422 and body contains `"error":"unknown_unit"`: pause, tell the user the unit symbol isn't in `warehouse.units`, and ask if they want to add it. If yes, edit `~/dev/BuildCanada/york_factory/db/seeds/kpis/units.yml` to add the row with the right `kind`/`base_unit`/`scale`, then `bin/rails kpis:seed_reference`, then retry. **Do not invent units** — that's what made v1 unit handling messy.

### Step 6 — Post citations in bulk

Build one JSON array with every value cell from the PDF table, then POST once. Top-level `agent_run_id` stamps every citation in the batch.

```bash
curl -s -X POST "$API/api/v1/kpis/admin/citations" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d "$(jq -n \
        --argjson rid $RUN_ID \
        --argjson rows "$CITATIONS_JSON" \
        '{agent_run_id:$rid, citations:$rows}')"
# → { "inserted": 47, "skipped_duplicate": 0, "ids": [...] }
```

Each row in `$CITATIONS_JSON`:
```json
{"measure_id": 5678, "measurement_year": 2024, "value_type": "actual",
 "value_numeric": 2.2, "document_id": 1234, "page_number": 5,
 "notes": "Methodology change: includes streaming TV starting 2024."}
```

Use `value_text` instead of `value_numeric` if the unit is qualitative (`pass/fail`, `text`, `date`). Use `notes` freely — it survives in the database verbatim.

### Step 7 — Close the run with a report

Compose a markdown report. Same structure as the existing `~/dev/toronto-budgets/edc_kpis.md`:

```markdown
# <Agency canonical name> — <fiscal_year> KPI extract

Source: <doc_url> (PDF, <N> pages)
Run: <RUN_ID>

## Headline findings
- 1–3 bullets about what jumps out (big misses, big wins, methodology shifts).

## Year-by-year KPIs

### <fiscal_year - 2> (actual)
- <Measure A>: <value> <unit>; <note>
- ...

### <fiscal_year> (target)
- ...

## Methodology shifts
- <Measure X> replaced by <Measure Y> in <year>. (If known, plan to add to measure_lineages.)

## Gaps / caveats
- <Measure Z>: 2024 cell unreadable on page 6.
- Years not covered by this PDF: ...
```

Then PATCH:

```bash
curl -s -X PATCH "$API/api/v1/kpis/admin/agent_runs/$RUN_ID" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d "$(jq -n \
        --arg report "$REPORT_MD" \
        --argjson summary "$SUMMARY_JSON" \
        '{agent_run: {status:"completed", report:$report, summary:$summary}}')"
```

`$SUMMARY_JSON` is structured counts you computed along the way:
```json
{"documents":1, "measures_created":3, "measures_existing":9,
 "citations_inserted":47, "citations_skipped":0,
 "unknown_units":[], "unreadable_cells":["measure X / 2024 / actual"]}
```

If anything went unrecoverably wrong, PATCH with `status:"failed"` and `error_message`. Don't leave a run in `running` state.

## After every successful run, report to the user

- The `agent_run_id` (so the user can `GET /api/v1/kpis/agent_runs/<id>` later).
- The summary counts.
- Any methodology shifts you flagged for follow-up `measure_lineages`.
- Any units that needed adding to `units.yml`.

## Caveats

- Some agencies (Mayor's Office, Council, accountability officers) have minimal performance measures — expect 0–3 KPIs.
- 2019–2020 docs are often shorter (one consolidated page); 2017–2018 have richer per-service breakdowns.
- COVID (2020–2022) disrupts comparability — flag in `notes`.
- The agency canonical name can change between years (e.g., "Civic Theatres Toronto" → "TO Live" in 2020). These are modelled as *separate organization rows* in York Factory linked by `organization_lineages` — make sure you pick the slug for the right era. If the budget year is post-rename, use the new slug; cite both names in the report's "Methodology shifts" section.
- Capital-only docs almost never carry KPIs — skip them.
- Briefing notes carry KPIs in 2020–2022 and 2026; budget notes in 2023–2025; operating notes in 2017–2018; analyst notes in 2019. Know which `doc_type` you're reading.
