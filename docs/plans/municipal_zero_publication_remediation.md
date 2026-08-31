# Municipal zero-publication remediation

This follow-up starts only after `script/run_national_financial_finalization.zsh` exits successfully
and its final coverage, test, build, local, and tunnel artifacts exist. It must not overlap the
frozen finalizer or write to any of its output paths.

## 1. Establish the post-finalization gap

- Recompute collected municipalities and approved detailed years from release `2026-08-27`.
- Resolve shared PDF slots by `[asset_sha256, fiscal_year_end]` using the existing variant priority
  and document-id ownership rules. Do not use a naive candidate-minus-approved count.
- Save a refuse-if-present `gap_census-<stamp>.json` containing every gap municipality and all of
  its candidate documents, years, variants, hashes, and headline/detailed extraction states.

## 2. Reuse the existing extraction machinery

- For every municipality without an approved detailed year, select the newest candidate, then the
  existing variant priority, then the lowest document id.
- Run bounded `process_municipal_financial_statements.rb --document-ids` lanes against a new output
  root and run a finite `review_extracted_municipal_financial_statements.rb --batch-size N` pass.
- Reuse the shared OCR cache. Do not add pipeline classes, prompts, reviewer identities, or watch
  sessions.
- Iterate the next-newest candidate year only while the municipality remains unpublished. Stop
  when one detailed year is approved or every candidate year is terminal with saved checks.

## 3. Derive exhaustion and gate York

- Save `exhausted_evidence-<stamp>.json`; exhaustion is derived only when every candidate year has
  a terminal detailed extraction with checks, error evidence, and review provenance. Do not add an
  `exhausted` database state.
- Assert zero active headline/detailed rows, shared-asset-aware reconciliation, deterministic
  reviewers for approvals, and that every gap-census municipality is approved or mechanically
  exhausted.
- Write a fresh coverage audit and run the same York tests, RuboCop targets, and Zeitwerk check as
  the national finalizer.

## 4. Represent every collected municipality safely

- Add a read-only York endpoint, or an explicit `include=collected` index mode, returning every
  collected municipality with its published years and `published` or derived `exhausted` status.
- Never return financial facts or line items from unapproved extractions.
- Make CanadaSpends list all collected municipalities. Published entries route only to approved
  years; exhausted entries route to a source/status page based on the existing First Nations
  no-data pattern and render no financial numbers.
- Add a runtime approval guard and pure-function tests for routing/status behavior. Treat
  `pnpm test` and `pnpm build` as smoke checks, not sufficient completion evidence.

## 5. Verify the actual user surface

Test locally and through a fresh Cloudflare tunnel against several municipalities newly approved by
the remediation pass, at least one exhausted municipality with zero numeric leakage, and Toronto as
a regression case. Save the API responses, rendered pages, redirects, and test logs with the run.
