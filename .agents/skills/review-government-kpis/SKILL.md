---
name: review-government-kpis
description: Independently review pending extracted KPI observations against their source documents and approve, correct, or reject each one through the York Factory KPI admin API. Approval promotes a claim into warehouse.canonical_observations. Use when an agent needs to work through the KPI review queue, validate extracted observations, or close out review flags after an ingestion run.
---

# Review Government KPIs

Work through the review queue of pending `warehouse.extracted_observations` and decide each one: approve as-is, approve with corrections, or reject. Approval is the gate into `canonical_observations` — the trusted data the website serves — so every decision must be verified against the source document, not against the extractor's claim.

One invocation reviews one scope: one agent run, one document, or one organization's queue.

## Hard Rules

- This skill must run independently of extraction. Never review observations extracted earlier in the same conversation or by the same agent invocation — re-read the source yourself.
- Verify every observation against the source document before deciding. Never approve from `evidence_quote` alone; the quote is part of the claim under review.
- If the source document cannot be fetched or the cited page/section cannot be located, leave the observation pending and add a review flag. Never approve unverifiable claims.
- Answer every open flag before approving. Approval auto-resolves open flags, so approving with an unanswered flag silently buries the question.
- Approve with `new_value` corrections only for mechanical errors you verified in the source (wrong page number, transcription slip, unit multiplier misapplied). If the fix changes what the observation *means* — different measure, different period, different concept — reject instead and report it for re-extraction.
- Reject when the value does not match the source, the measure assignment is wrong, the value is a duplicate of a sibling observation, or the claim cannot be located in the document.
- Use `reviewer: "agent:review-government-kpis run:<RUN_ID>"` so decisions are traceable to this run.
- Do not re-approve or re-reject observations that already have a decision (`review_status` is `approved` or `rejected`).

## Preflight

```bash
API="${YORK_FACTORY_API_URL:-http://localhost:3000}"
TOKEN="${YORK_FACTORY_KPI_TOKEN:-$(cat ~/.config/york-factory/kpi-token 2>/dev/null)}"
test -n "$TOKEN" || { echo "Missing YORK_FACTORY_KPI_TOKEN"; exit 1; }
curl -sf "$API/up" >/dev/null || { echo "Start the Rails server: bin/rails server"; exit 1; }
```

Every write request needs:

```bash
-H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json"
```

## Workflow

### 1. Open Agent Run

```bash
RUN=$(curl -s -X POST "$API/api/v1/kpis/admin/agent_runs" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d "$(jq -n \
    --arg version "$(git rev-parse --short HEAD 2>/dev/null || echo unknown)" \
    --argjson input "$INPUT_PARAMS_JSON" \
    '{agent_run:{
      agent_name:"review-government-kpis",
      agent_version:$version,
      input_params:$input
    }}')")
RUN_ID=$(echo "$RUN" | jq -r '.id')
test "$RUN_ID" != "null" || { echo "$RUN"; exit 1; }
REVIEWER="agent:review-government-kpis run:$RUN_ID"
```

`INPUT_PARAMS_JSON` records the review scope, e.g. `{"agent_run_id": 42}` or `{"organization_slug": "ttc"}`.

### 2. Pull The Queue

Filters: `jurisdiction_slug`, `organization_slug`, `measure_id`, `document_id`, `agent_run_id`, `min_severity`, `has_open_flags`, `per_page`.

```bash
curl -s "$API/api/v1/kpis/admin/review_queue?agent_run_id=$TARGET_RUN_ID&per_page=100" \
  -H "Authorization: Bearer $TOKEN" \
  | jq '.data[] | {extracted_observation_id, measure: .measure.canonical_name,
                   measurement_year, value_type, value_numeric, value_raw,
                   source_page, evidence_quote, extraction_confidence,
                   open_flags, document: .document.doc_url}'
```

Each entry includes `open_flags` with `flag_type`, `severity`, `message`, and `evidence` — these are the questions a previous agent could not answer. Page through until the scope is exhausted.

For full observation detail (period fields, organization attributions, notes), use the public citations endpoint:

```bash
curl -s "$API/api/v1/kpis/citations?agent_run_id=$TARGET_RUN_ID&review_status=pending&per_page=100"
```

### 3. Verify Each Observation Against The Source

Group queue entries by `document_id` and fetch each source document once. Read the cited `source_page` / `source_section` / `source_table` directly.

Check, in order:

1. **Locate**: the metric named by `metric_name_raw` exists on the cited page/section. If not found there, search the document before concluding it is absent.
2. **Value**: the source cell matches `value_raw` exactly, and `value_numeric` is the correct display-unit conversion of it. Recompute multiplier conversions yourself (a table in `$000s` showing `5,300` with unit `$M` must have `value_numeric: 5.3`).
3. **Type**: actual vs target vs plan vs budget matches the source column. Target/actual confusion is the most common extraction error.
4. **Period**: `measurement_year` follows the convention (federal `2024-25` → `2025`), and `period_basis`/`period_start`/`period_end` match what the source says.
5. **Measure assignment**: the observation's measure (`measure.canonical_name`) means the same thing as the source row. A renamed or redefined metric belongs on a new measure, not this one.
6. **Attribution**: observed/responsible organization and geography match the source.
7. **Footnotes**: scan for footnote markers on the source cell that change interpretation (exclusions, restatements, methodology changes). If the source cell carries a marker, the observation must have that footnote linked and the marker must not be glued into `value_raw`/`value_text`; a missing link or a glued marker is a mechanical correction. A footnote that redefines the metric (population base, constant-dollar base, retirement) is grounds for rejection, not correction.
8. **No-result cells**: a cell reading `N/A`, `not available`, `—`, or `TBD` should never have been extracted — reject it; there is no value to canonicalize.
9. **Siblings**: if the same measure/year/value_type already has an approved sibling, this one is likely a duplicate or a restatement — compare before deciding.
10. **Open flags**: resolve each flag's question explicitly against the source. The answer goes in the decision notes.

### 4. Decide

**Approve as-is** — everything checks out:

```bash
curl -s -X POST "$API/api/v1/kpis/admin/extracted_observations/$OBS_ID/approve" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d "$(jq -n --arg reviewer "$REVIEWER" \
    --arg notes "Verified against p.12: value, type, period, and unit all match. Flag 'unit_ambiguous' resolved: footnote 2 confirms \$ millions." \
    '{reviewer:$reviewer, notes:$notes}')"
```

**Approve with corrections** — mechanical error, verified fix:

```bash
curl -s -X POST "$API/api/v1/kpis/admin/extracted_observations/$OBS_ID/approve" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d "$(jq -n --arg reviewer "$REVIEWER" \
    --arg notes "Source shows 83.4, extractor wrote 83. Corrected." \
    '{reviewer:$reviewer, notes:$notes, new_value:{value_numeric:83.4}}')"
```

`new_value` accepts the reviewer-editable fields: value fields, period fields, source location fields, organization/geography attributions, `measure_id`, and `notes`. Always state in `notes` what was wrong and how the source supports the fix.

**Reject** — wrong, duplicate, or not in the source:

```bash
curl -s -X POST "$API/api/v1/kpis/admin/extracted_observations/$OBS_ID/reject" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d "$(jq -n --arg reviewer "$REVIEWER" \
    --arg notes "Source p.12 shows this as the 2025-26 target, not a 2024-25 actual. Needs re-extraction with value_type: target." \
    '{reviewer:$reviewer, notes:$notes}')"
```

**Leave pending** — cannot verify (document unreachable, page unreadable, genuinely ambiguous):

```bash
curl -s -X POST "$API/api/v1/kpis/admin/extracted_observations/$OBS_ID/review_flags" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"flag_type":"source_unverifiable","severity":"high","message":"Document URL returns 404; cannot verify any cell on this claim."}'
```

Notes are mandatory on every approve and reject: cite the page/section you read and, when flags were open, the answer to each flag.

### 5. Close The Run

```bash
curl -s -X PATCH "$API/api/v1/kpis/admin/agent_runs/$RUN_ID" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d "$(jq -n \
    --arg report "$REPORT_MD" \
    --argjson summary "$SUMMARY_JSON" \
    '{agent_run:{status:"completed", report:$report, summary:$summary}}')"
```

The final report should include:

- the review scope (run/document/organization) and queue size at start
- counts: approved as-is, approved with corrections, rejected, left pending
- every correction made, with the source evidence for it
- every rejection, with the reason and whether re-extraction is needed
- observations left pending and exactly what blocks them
- patterns worth fixing upstream (e.g., "extractor consistently misread the target column for this document family")
