# Municipal budget acquisition contract

This is a discovery and archival contract for a future public-institution release. It must not
write to the pinned `2026-08-27` release or share extraction rows with audited financial
statements.

## Document identity

- Document type: `budget`
- Canonical ID: `ca/{province}/{municipality}/documents/budgets/{fiscal_year}/{variant}`
- `fiscal_year` is the year being budgeted for, not the publication or retrieval year.
- Allowed variants: `operating`, `capital`, and `consolidated`.
- A consolidated budget is preferred when it contains both operating and capital plans. Separate
  operating and capital documents may coexist for the same municipality-year.

Budgets and audited financial statements for the same municipality-year are separate publishable
works. Budget records must never enter the financial-statements API arrays, audited-statement
Sankey, or audited institution-year publication slots.

## Region ownership

- West: `bc`, `ab`, `sk`, `mb`
- Central: `on`, `qc`
- Atlantic and territories: `nb`, `ns`, `pe`, `nl`, `yt`, `nt`, `nu`

Each worker owns only its region's batch and log. Cross-listed or shared documents may resolve to
the same content-addressed asset without coordinating manifest writes.

## JSONL record

Every terminal discovery candidate, including failures, is one JSON object with these fields:

```json
{
  "institution_canonical_id": "ca/on/example",
  "institution_name": "Example",
  "province": "on",
  "fiscal_year": 2026,
  "document_type": "budget",
  "document_variant": "consolidated",
  "canonical_id": "ca/on/example/documents/budgets/2026/consolidated",
  "title": "2026 Approved Budget",
  "language": "en",
  "source_page_url": "https://example.ca/budget",
  "download_url": "https://example.ca/2026-budget.pdf",
  "retrieved_at": "2026-08-30T00:00:00Z",
  "content_sha256": "64 lowercase hexadecimal characters",
  "archive_path": "sha256/ab/abcdef...pdf",
  "mime_type": "application/pdf",
  "byte_size": 123456,
  "status": "archived",
  "checks": [
    {"id": "official_source", "status": "pass", "detail": "municipal website"},
    {"id": "pdf_signature", "status": "pass", "detail": "%PDF-"},
    {"id": "sha256", "status": "pass", "detail": "matches archived bytes"},
    {"id": "issuer", "status": "pass", "detail": "title/source identifies ca/on/example"},
    {"id": "fiscal_year", "status": "pass", "detail": "budgeted year is 2026"},
    {"id": "budget_variant", "status": "pass", "detail": "operating and capital sections"}
  ]
}
```

Failed candidates retain the URLs and evidence available, set `status` to `failed`, leave
unavailable asset fields null, and save at least one failing check with a concrete reason. A record
is not terminal unless `checks` is a non-empty array.

## Source and archival rules

1. Use official municipal or official provincial repositories as the final source. Search engines
   may discover a page but are not evidence.
2. Collect all available historical approved/adopted budgets. Draft consultation material and
   budget highlights are not substitutes for full budgets.
3. Discovery is network-bound only while financial-statement extraction is active: no OCR, PDF
   rendering, model extraction, or database connections.
4. Rate-limit requests per host and reuse the existing municipal scraper conventions.
5. Verify disk headroom before downloads.
6. Write assets atomically: download to a temporary file, verify `%PDF-`, size, and SHA-256, then
   rename into the shared asset store at
   `/Volumes/floppy/york_factory/public_institutions/assets/sha256/{prefix}/{sha256}.pdf`.
   Treat an already-valid destination as archived and never overwrite it in place.
7. Write JSONL through a temporary region-owned file and atomically promote checkpoints. Never
   allow a partial JSON line.

## Agent prohibitions and checkpoint

Discovery workers must not connect to the database, edit repository files, run git commands,
operate tmux, alter financial-statement processes, or write outside their own regional batch/log
and the shared content-addressed asset store.

Stop after the first 10 terminal candidates in each region for schema and source-quality review.
Resume the full regional crawl only after that checkpoint passes.
