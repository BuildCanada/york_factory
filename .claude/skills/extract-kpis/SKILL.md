---
name: extract-kpis
description: Extract performance measures / KPIs from any Canadian government budget or performance PDF (federal Departmental Plans, provincial Annual Business Plans, municipal budget notes), and POST them to the York Factory admin API. Every write is tagged with an agent_run row for traceability. Use when the user asks to extract, populate, or backfill KPIs / performance measures / service indicators for any government organization in `warehouse.jurisdictions` (e.g., "extract KPIs from the CRA 2026 Departmental Plan", "populate TTC performance measures for 2027", "ingest BC Health 2025 annual report measures").
allowed-tools:
  - Bash
  - Read
  - AskUserQuestion
---

# Government KPI / performance-measure extractor → York Factory

Extracts the performance-measure tables from a single government PDF (one jurisdiction × one organization × one fiscal year), posts the data to the York Factory admin API, and submits a markdown report attached to a `warehouse.agent_runs` row so the entire extraction is queryable.

Jurisdiction-neutral. Works for federal departments (Departmental Plans, Departmental Results Reports), provincial/territorial agencies (Annual Business Plans, Annual Reports), municipalities (operating-budget notes, briefing notes), and crown corporations (annual reports).

The earlier global skill `~/.claude/skills/toronto-budget-kpis/` is the legacy SQLite-writing predecessor — that data was already bulk-loaded into York Factory via `kpis:import_toronto_v1`. Use *this* skill going forward.

## When to use

- "Extract KPIs from the CRA 2026 Departmental Plan"
- "Add Alberta Health 2025 annual report performance indicators"
- "Backfill TTC performance measures for 2027"
- "Ingest the new Vancouver operating budget KPIs"

One invocation = one PDF = one `agent_run`. Multiple PDFs (different orgs, different years, different jurisdictions) → multiple invocations.

## Pre-flight

### 1. API token

Resolve in this order:
1. `$YORK_FACTORY_KPI_TOKEN` (env var)
2. `~/.config/york-factory/kpi-token` (file, chmod 600)

If neither exists, instruct the user to issue one:

```bash
cd ~/dev/BuildCanada/york_factory
bin/rails kpis:issue_token name=extract-kpis
# copy the printed token (starts with yfk_), then:
mkdir -p ~/.config/york-factory
echo 'yfk_...' > ~/.config/york-factory/kpi-token
chmod 600 ~/.config/york-factory/kpi-token
```

### 2. API base URL

`$YORK_FACTORY_API_URL`, default `http://localhost:3000`. The skill needs the Rails server running. If `curl -sf "$API/up"` fails, ask the user to start `bin/rails server` from the york_factory repo before proceeding.

### Setup snippet (run at start of every invocation)

```bash
TOKEN="${YORK_FACTORY_KPI_TOKEN:-$(cat ~/.config/york-factory/kpi-token 2>/dev/null)}"
[ -z "$TOKEN" ] && { echo "no token — see pre-flight in SKILL.md"; exit 1; }
API="${YORK_FACTORY_API_URL:-http://localhost:3000}"
curl -sf "$API/up" >/dev/null || { echo "$API not reachable — start \`bin/rails server\`"; exit 1; }
```

## Workflow

### Step 1 — Resolve the jurisdiction

The user's term may be a country, province, or city. List all known jurisdictions and pick the right one:

```bash
curl -s "$API/api/v1/kpis/jurisdictions" \
  | jq '.data[] | {slug, name, level, region_code}'
```

Common slugs to expect: `ca` (Canada federal), `ab` / `bc` / `on` / ... (provinces), `nu` / `nt` / `yt` (territories), `toronto` (municipal). If the user's target jurisdiction doesn't exist yet (e.g., another city), pause and tell the user to seed it (the trade-barriers seed file at `db/seeds/trade_barriers_jurisdictions.rb` is the existing pattern for provinces; municipal rows go through `kpis:seed_reference` after editing `db/seeds/kpis/*.yml`). Do not invent jurisdiction rows from the skill.

Store as `JURISDICTION_SLUG`.

### Step 2 — Resolve the organization within that jurisdiction

```bash
curl -s "$API/api/v1/kpis/jurisdictions/$JURISDICTION_SLUG/organizations" \
  | jq '.data[] | select(.canonical_name | test("'"$ORG_TERM"'"; "i"))
                 | {slug, canonical_name, active_from_year, active_to_year}'
```

- **Exactly one match** → use its `slug`.
- **Multiple matches** → show all and ask the user which.
- **No match** → list every org for that jurisdiction (the user's term might be an alias of a different canonical name) and confirm before lazy-creating in the next step.

If the user confirms the org doesn't exist yet, **lazy-create it** via the admin API:

```bash
NEW_ORG=$(curl -s -X POST "$API/api/v1/kpis/admin/organizations" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d "$(jq -n \
        --arg jur "$JURISDICTION_SLUG" --arg slug "$ORG_SLUG" \
        --arg name "$CANONICAL_NAME" --arg kind "$KIND" \
        --argjson aliases "$ALIASES_JSON" \
        '{organization: {jurisdiction_slug:$jur, slug:$slug, canonical_name:$name,
                         kind:$kind, aliases:$aliases}}')")
ORG_SLUG=$(echo "$NEW_ORG" | jq -r .slug)
```

`$KIND` is typically `"department"`, `"agency"`, or `"crown_corp"` (free text — see existing rows for the conventions used in each jurisdiction). `$ALIASES_JSON` is a JSON array of any acronyms or alternate names you've seen in source documents (e.g., `["PCH", "Department of Canadian Heritage"]`).

Lazy-create is idempotent on `(jurisdiction_slug, slug)` — if the slug already exists, the response returns the existing row with `created: false` and no new aliases beyond what you sent are added.

Store as `ORG_SLUG`.

**Important:** Lazy-create handles new orgs that have no lineage relationship with existing rows. If the new org is the *successor* of a renamed or absorbed predecessor that already exists, also POST a `/admin/organization_lineages` row after the create so the relationship is tracked. The skill should flag this to the user when it spots phrasing like "formerly known as" or "merged with" in the source doc.

### Step 3 — Open an agent run

```bash
RUN=$(curl -s -X POST "$API/api/v1/kpis/admin/agent_runs" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d "$(jq -n \
        --arg jur "$JURISDICTION_SLUG" --arg org "$ORG_SLUG" \
        --argjson yr $FISCAL_YEAR --arg url "$DOC_URL" \
        --arg ver "$(cd ~/dev/BuildCanada/york_factory && git rev-parse --short HEAD)" \
        '{agent_run: {agent_name:"extract-kpis",
                      agent_version:$ver,
                      input_params:{jurisdiction_slug:$jur,
                                    organization_slug:$org,
                                    fiscal_year:$yr,
                                    doc_url:$url}}}')")
RUN_ID=$(echo "$RUN" | jq .id)
```

If `RUN_ID` is null, abort and report the response. Every subsequent call passes `agent_run_id: $RUN_ID` so the writes are traceable.

### Step 4 — Register the PDF document

The user gives you a PDF URL (canonical source) and optionally a local file path for the actual reading. Use the URL as the natural key — `doc_url` is unique in the API, so re-posting the same URL returns the same `id`.

```bash
DOC=$(curl -s -X POST "$API/api/v1/kpis/admin/documents" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d "$(jq -n \
        --arg jur "$JURISDICTION_SLUG" --arg org "$ORG_SLUG" \
        --argjson yr $FISCAL_YEAR --arg url "$DOC_URL" --arg title "$DOC_TITLE" \
        --argjson rid $RUN_ID \
        '{document: {jurisdiction_slug:$jur, organization_slug:$org,
                     fiscal_year:$yr, doc_url:$url, doc_title:$title,
                     agent_run_id:$rid}}')")
DOC_ID=$(echo "$DOC" | jq .id)
```

### Step 5 — Read the source document

Federal departments publish Departmental Plans / Results Reports as **HTML** (no PDF). Provincial and municipal sources are mostly **PDF**. Pick the right branch.

#### 5a. PDF branch (provincial, municipal, older federal)

Use the `Read` tool with the `pages:` argument. **Don't load the whole PDF.**

1. Read pages 1–3 to get the TOC / overview.
2. Look for headings indicating performance content. Common across jurisdictions:
   - **Provincial/territorial:** "Performance Measures", "Outcomes and Performance Measures", "Strategic Outcomes", "Annual Business Plan — Results"
   - **Municipal:** "Service Performance", "Key Service Levels", "Performance Measures", "Service Outcomes"
   - **Older federal PDFs:** "Departmental Plan — Results", "Performance Indicators", "Results to Date"
3. Jump to those pages with `Read(pages: "N-M")`.
4. Populate `page_number` on each citation with the **physical PDF page index** (1-based, as the Read tool numbers).

#### 5b. HTML branch (current federal, some provincial)

Federal Departmental Results Reports follow a standard TBS structure: each Core Responsibility is an `<h3 id="a3X">` heading containing one or more performance-indicator tables. Table structure: `Departmental result indicator | Target | Date to achieve target | Actual results`, with actuals as concatenated `FYstart–end: value` text.

```bash
curl -sL "$DOC_URL" > /tmp/extract-kpis-source.html
```

Then parse with a small Python helper (the skill includes one as a reference). The fiscal-year convention: federal `YYYY-YY` notation refers to April-to-March; use the *end* year as `measurement_year` (so `2024-25` → `measurement_year: 2025`).

`page_number` is left null for HTML sources. Use `service_category` to record the Core Responsibility (federal) or section heading (provincial), and `notes` to capture the exact result-statement under which the indicator lives.

A reusable Python parser for federal DRRs lives at the end of this skill (see "Reference: federal DRR HTML parser"). Adapt the table-extraction regex for other HTML formats as needed.

For each measure row in each performance table, capture:
- `canonical_name` — wording exactly as it appears in the PDF heading.
- `unit_symbol` — must already exist in `warehouse.units`. Common symbols: `#`, `%`, `$`, `$M`, `$B`, `count`, `count_thousands`, `seconds`, `hours`, `days`, `business_days`, `score`, `index`, `rating`, `pass/fail`, `text`, `date`. If unsure, try the POST — the API returns 422 `error: "unknown_unit"` for unknown symbols.
- `service_category` — the section heading the measure sits under.
- For each year column in the row: one citation row with `measurement_year`, `value_type`, `value_numeric` (or `value_text`), `page_number`, and `notes` for anything unusual.

**`value_type` rules (jurisdiction-neutral):**
- Years before the budget/fiscal year of the document: `actual`
- The document's fiscal year: `budget` if labeled "Budget", `target` if "Target", `plan` if "Plan", `projected` if "Projected/Forecast"
- Future plan years: `plan` or `projected` per labeling
- The same `(measure, measurement_year, value_type)` reported in multiple documents is a *feature* — each citation has its own `document_id`, and `warehouse.measure_facts` resolves to the latest published doc. This is how restatements get tracked. Insert all of them.

**Critical conventions (apply everywhere):**
- **`page_number`** = physical PDF page index (1-based) as the `Read` tool numbers them. Not printed page numbers. Leave null for HTML sources.
- **Don't fabricate.** If a cell is unreadable, skip it; record the gap in the report.
- **Methodology shift = separate measure**, not the same. If a 2026 doc replaces "Jobs Created and Retained" with "Businesses Provided with Material Support", create two distinct measures. Capture the predecessor → successor relationship later via `POST /api/v1/kpis/admin/measure_lineages` if known.
- **Minor name variant = same measure.** "Film Production Spending" → "Film and Television Production Spending" is one measure; keep one canonical_name.
- **Federal fiscal year notation:** `2024-25` (April 2024–March 2025) → `measurement_year: 2025` (use the end year).

### Step 6 — Upsert measures

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

If the response is 422 with `"error":"unknown_unit"`: pause, tell the user the unit symbol isn't in `warehouse.units`, and ask if they want to add it. If yes, edit `db/seeds/kpis/units.yml` with the right `kind`/`base_unit`/`scale`, then `bin/rails kpis:seed_reference`, then retry. **Do not invent units** — that's exactly what made v1 unit handling messy in the Toronto import.

### Step 7 — Post citations in bulk

Build one JSON array with every cell from every performance table, then POST once. Top-level `agent_run_id` stamps every citation in the batch.

```bash
curl -s -X POST "$API/api/v1/kpis/admin/citations" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d "$(jq -n \
        --argjson rid $RUN_ID \
        --argjson rows "$CITATIONS_JSON" \
        '{agent_run_id:$rid, citations:$rows}')"
# → { "inserted": 47, "skipped_duplicate": 0, "ids": [...] }
```

Each row:
```json
{"measure_id": 5678, "measurement_year": 2024, "value_type": "actual",
 "value_numeric": 2.2, "document_id": 1234, "page_number": 5,
 "notes": "Methodology change: includes streaming starting 2024."}
```

Use `value_text` instead of `value_numeric` if the unit is qualitative (`pass/fail`, `text`, `date`). Use `notes` freely — it survives in the database verbatim.

### Step 8 — Close the run with a report

Compose a markdown report:

```markdown
# <Org canonical name> (<Jurisdiction>) — <fiscal_year> KPI extract

Source: <doc_url> (<doc_type>, <N> pages)
Run: <RUN_ID>

## Headline findings
- 1–3 bullets about what jumps out (big misses, big wins, methodology shifts).

## Year-by-year KPIs

### <fiscal_year - 2> (actual)
- <Measure A>: <value> <unit>; <note if any>
- ...

### <fiscal_year> (target / budget / plan)
- ...

## Methodology shifts
- <Measure X> replaced by <Measure Y> in <year>. (Follow-up: register in measure_lineages.)

## Gaps / caveats
- <Measure Z>: 2024 cell unreadable on page 6.
- Years not covered by this PDF: ...
```

PATCH the run to close it:

```bash
curl -s -X PATCH "$API/api/v1/kpis/admin/agent_runs/$RUN_ID" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d "$(jq -n \
        --arg report "$REPORT_MD" \
        --argjson summary "$SUMMARY_JSON" \
        '{agent_run: {status:"completed", report:$report, summary:$summary}}')"
```

`$SUMMARY_JSON` should be structured counts you computed along the way:
```json
{"documents":1, "measures_created":3, "measures_existing":9,
 "citations_inserted":47, "citations_skipped":0,
 "unknown_units":[], "unreadable_cells":["measure X / 2024 / actual"]}
```

If anything went unrecoverably wrong, PATCH with `status:"failed"` and `error_message`. Never leave a run in `running` state.

## After a successful run, report to the user

- The `agent_run_id` (so the user can `GET /api/v1/kpis/agent_runs/<id>` later).
- The summary counts.
- Any methodology shifts you flagged for follow-up `measure_lineages`.
- Any units that needed adding to `units.yml`.

## Jurisdictional gotchas (reference)

These are *examples* — neither exhaustive nor strict rules. Trust what the PDF actually shows.

**Federal (Canada):**
- Performance content lives in Departmental Plans (forward-looking, indicators only) and Departmental Results Reports (results-to-date). Most indicators are in tables under "Core Responsibilities" sections, often pages 10–30.
- Common units: `count`, `%`, `$M`, `pass/fail`.
- Fiscal year starts April 1.

**Provincial / territorial:**
- Annual Business Plans (forward) and Annual Reports (results). Strategic outcomes often listed first, with performance measures in tables underneath.
- Different provinces use different terminology (Alberta: "Performance Measures and Indicators"; BC: "Performance Measures"; Ontario: "Annual Report" highlights).
- Fiscal year starts April 1 (most) or January 1 (some agencies).

**Municipal:**
- Operating budget notes carry performance measures in tables near the end (typically last third of the doc). Toronto specifically uses "Service Performance" headings on pages 4–6 of post-2019 notes. Other municipalities vary widely.
- Fiscal year is calendar year for most Canadian municipalities.

**Universal:**
- Measures don't carry over cleanly across all years. Expect coverage gaps. Don't try to "fill in" missing values.
- Methodology footnotes in the source often signal a methodology shift — read them and create separate measures when warranted.
- Capital-only documents almost never carry KPIs — skip them.
- COVID years (2020–2022) disrupt comparability for many programs — flag in `notes` when relevant.

## Reference: federal DRR HTML parser

Used in real extractions for departments whose DRR is HTML-only (PCH, ESDC, ECCC, etc.). Save as a one-shot script, adjust selectors for variants:

```python
import re, json, urllib.request
from html import unescape

def strip_tags(s):
    s = re.sub(r'<[^>]+>', ' ', s)
    return re.sub(r'\s+', ' ', unescape(s)).strip()

def parse_value(text):
    text = text.strip()
    if not text or text.lower() in ('n/a', 'not available', '-', ''):
        return None, None, None
    for pat, unit in [
        (r'^\$?\s*([\d,\.]+)\s*billion\b', "$B"),
        (r'^\$?\s*([\d,\.]+)\s*million\b', "$M"),
        (r'^([\d\.,]+)\s*%',               "%"),
        (r'^\$\s*([\d,\.]+)\b',            "$"),
        (r'^([\d,]+(?:\.\d+)?)',           "count"),
    ]:
        m = re.match(pat, text, re.I)
        if m: return float(m.group(1).replace(',','')), unit, None
    return None, "text", text

YEAR_RE = re.compile(r'(\d{4})[–\-](\d{2,4})\s*:\s*')

def parse_actuals(cell):
    cell = re.sub(r'Footnote\s*\d+', '', cell)
    markers = list(YEAR_RE.finditer(cell))
    out = []
    for i, m in enumerate(markers):
        end = int(m.group(1)) + 1   # FY end-year
        val_start = m.end()
        val_end = markers[i+1].start() if i+1 < len(markers) else len(cell)
        out.append((end, cell[val_start:val_end].strip()))
    return out

def extract_drr(html):
    sections = re.split(r'<h3 id="(a3[a-z])"[^>]*>([^<]+)</h3>', html)
    out = []
    for i in range(1, len(sections), 3):
        cr_title = sections[i+1]
        body = sections[i+2] if i+2 < len(sections) else ""
        if "Internal services" in cr_title:
            continue
        for tbl in re.findall(r'<table[^>]*>.*?</table>', body, re.DOTALL):
            plain = strip_tags(tbl)
            result_stmt = (re.match(
                r'^Table \d+ shows.*?under (.+?) in the last three fiscal years\.',
                plain) or [None, None])[1]
            for row in re.findall(r'<tr[^>]*>(.*?)</tr>', tbl, re.DOTALL):
                cells = [strip_tags(c) for c in
                         re.findall(r'<t[dh][^>]*>(.*?)</t[dh]>', row, re.DOTALL)]
                if len(cells) != 4 or cells[0].lower().startswith('departmental result indicator'):
                    continue
                indicator = re.sub(r'\s*Footnote\s*\d+\s*$', '', cells[0]).strip()
                target_v, target_u, _ = parse_value(cells[1])
                actuals = parse_actuals(cells[3])
                unit = target_u
                if unit in (None, "text"):
                    for _, raw in actuals:
                        _, u, _ = parse_value(raw)
                        if u and u != "text": unit = u; break
                out.append({
                    "canonical_name": indicator,
                    "service_category": result_stmt or cr_title,
                    "unit_symbol": unit or "count",
                    "target_value": target_v, "target_raw": cells[1],
                    "target_date": cells[2], "actuals": actuals,
                })
    return out

# Usage:
# html = urllib.request.urlopen(DOC_URL).read().decode()
# measures = extract_drr(html)
```
