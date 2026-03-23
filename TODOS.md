# TODOS

## P2: Automatic Data Freshness Alerts

When the nightly health check detects new government data (e.g., new Supplementary Estimates published), automatically trigger ingestion and notify subscribers via webhook/Slack/email. Highlight the biggest changes in the new data.

**Why:** York Factory should be a living system, not a static database. Journalists and researchers want to know when new data drops.

**Context:** The nightly health check job is already in v1 scope — it checks source URLs for HTTP 200. This extends it to detect new data (by comparing checksums or last-modified headers) and trigger auto-ingestion. Notification plumbing needs design (webhook endpoint? Slack integration? Email list?). The anomaly detection feature (v1) can power the "biggest changes" highlighting.

**Depends on:** v1 pipeline running reliably for a few manual ingestion cycles. Trust the pipeline before automating it.

## P1: Government Procurement/Contracts (buyandsell.gc.ca)

Ingest procurement contract data from buyandsell.gc.ca to connect corporations to actual government spending. This is the missing link: corporate registry tells us WHO these entities are, fiscal data tells us HOW MUCH money flows, but procurement tells us WHO GETS THE MONEY.

**Why:** Corp registry without procurement = incomplete fraud picture. This is the highest-value next dataset.

**Depends on:** Corporate registry pipeline stable (v0.2.0).

## P1: Lobbying client_name → corporate_entities Cross-Reference

Match `lobbying_activities.client_name` against `corporate_entities.legal_name` to connect lobbyists to their corporate entities. Free value — data already exists in both tables.

**Why:** Reveals which corporations are lobbying which government entities while receiving contracts/funding.

**Depends on:** Corporate registry pipeline (v0.2.0).

## P2: Remaining 8 Provincial Scrapers (NS, NB, MB, PE, NL, YT, NT, NU)

Build scrapers for the 8 remaining provinces/territories. Seeds and source records already exist. Pattern validated with ON, AB, SK scrapers.

**Why:** Complete coverage of all Canadian jurisdictions.

**Context:** Each scraper needs manual HTML analysis of the provincial registry search page. ~30min CC effort per scraper. Mechanize + ProvincialScraping concern pattern already proven.

## P2: COPY Command for ODA Initial Load

Use PostgreSQL COPY FROM STDIN for the initial 10M-row ODA address load instead of upsert_all. Currently works but is ~10x slower than COPY.

**Why:** Performance — initial ODA load takes hours via upsert_all, minutes via COPY.

## P3: Community Contribution Pipeline

Let Build Canada community members submit new data sources to York Factory. They provide a source URL and schema description, York Factory's LLM generates a draft normalizer, and a maintainer reviews and approves it.

**Why:** This is how York Factory scales beyond what the team can maintain. The flywheel: more data → more tools built on York Factory → more contributors → more data.

**Context:** Needs a submission interface (web form or GitHub issue template), LLM-powered normalizer generation (using the extensibility pattern from v1), and a review/approval workflow. High implementation effort. Should only be attempted after the extensibility pattern is proven with 5+ manually added sources.

**Depends on:** Extensibility pattern proven with lobbying data and at least 3 additional sources. Open-source release (to invite community contributions).
