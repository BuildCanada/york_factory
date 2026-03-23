# York Factory — Canadian Fiscal Data Pipeline

## What is York Factory?
Automated pipeline that normalizes Canadian federal government fiscal data (Public Accounts, Main Estimates, Supplementary Estimates) into shared, queryable Postgres tables. Built for Build Canada's community of contributors who build government accountability tools.

## Commands
```bash
bin/rails test                    # run all tests
bin/rails db:migrate              # apply migrations
bin/rails db:seed                 # seed data sources
bin/rails console                 # Rails console
```

## Architecture
- **Rails 8 API** with Solid Queue (Postgres-backed jobs, no Redis)
- **Supabase** for managed Postgres (production uses DATABASE_URL)
- **Cloudflare R2** for raw CSV archival (S3-compatible)
- **Kamal** for deployment to OVH VPS

## Pipeline (associated objects pattern)
```
Source::Fetcher          → downloads CSV, archives to R2, creates RawIngestion
RawIngestion::InfobaseLoader    → deterministic ETL for InfoBase (Public Accounts)
RawIngestion::EstimatesNormalizer → LLM-powered entity resolution for Estimates
RawIngestion::LobbyingNormalizer  → lobbying registry normalization
Organization::EntityResolver     → shared entity resolution cascade
```

## Key gems
- `active_record-associated_object` — pipeline logic as associated objects
- `active_job-performs` — auto-generates job classes from methods
- `anthropic` — Claude API for entity resolution and NL queries
- `aws-sdk-s3` — R2 storage

## Entity resolution cascade
1. Exact match on organization_aliases
2. Case-insensitive match
3. Encoding normalization (curly quotes → straight)
4. LLM fuzzy match (Claude Haiku, top 5 candidates)
5. Confidence gate (>= 0.8 auto-accept, < 0.8 flag for review)

## Environment variables
- `DATABASE_URL` — Supabase Postgres connection
- `ANTHROPIC_API_KEY` — Claude API for entity resolution + NL queries
- `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `R2_ENDPOINT`, `R2_BUCKET` — Cloudflare R2
