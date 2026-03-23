# York Factory — Canadian Fiscal & Corporate Data Pipeline

## What is York Factory?
Automated pipeline that normalizes Canadian government fiscal data and corporate registry data into shared, queryable Postgres tables. Tracks government spending (Public Accounts, Estimates), lobbying activity, and corporate registrations across all Canadian jurisdictions. Built for Build Canada's community of contributors who build government accountability tools.

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
- **Cloudflare R2** for raw CSV/XML archival (S3-compatible)
- **Kamal** for deployment to OVH VPS
- **pg_trgm** extension for trigram similarity (fuzzy name matching at scale)

## Pipeline (associated objects pattern)
```
Source::Fetcher                        → downloads data, archives to R2, creates RawIngestion
                                         Dispatch hash maps source name regex → normalizer

Fiscal Pipeline:
  RawIngestion::InfobaseLoader         → deterministic ETL for InfoBase (Public Accounts)
  RawIngestion::EstimatesNormalizer    → LLM-powered entity resolution for Estimates
  RawIngestion::LobbyingNormalizer     → lobbying registry normalization
  GovernmentEntity::EntityResolver     → shared entity resolution cascade

Corporate Registry Pipeline:
  RawIngestion::CorporateNormalizer    → Federal ISED XML (SAX parser, 5K batch upserts)
  RawIngestion::OrgbookBcNormalizer    → BC OrgBook REST API (paginated)
  RawIngestion::QuebecRegistryNormalizer → Quebec Données Québec CSV ZIP (6 files, NEQ key)
  RawIngestion::OntarioObrScraper      → Ontario OBR HTML scraper (Mechanize)
  RawIngestion::AlbertaCoresScraper    → Alberta CORES HTML scraper
  RawIngestion::SaskatchewanIscScraper → Saskatchewan ISC HTML scraper

Enrichment Pipeline:
  RawIngestion::OdbizNormalizer        → Statistics Canada ODBiz CSV → BusinessEstablishment
  RawIngestion::OdaNormalizer          → Statistics Canada ODA CSV → StandardizedAddress
  CorporateEntity::Enricher           → ISED JSON API → directors for federal corps
```

## Data Model
```
GovernmentEntity (fiscal data: Public Accounts, Estimates, lobbying)
  ├── has_many :government_entity_aliases
  ├── has_many :fiscal_authorities, :fiscal_expenditures
  ├── has_many :lobbying_activities
  └── has_many :corporate_entities (cross-reference)

CorporateEntity (corporate registrations across all jurisdictions)
  ├── unique key: [jurisdiction, registry_id]
  ├── has_many :corporate_entity_aliases, :corporate_registrations
  ├── has_many :director_appointments → :corporate_directors
  ├── belongs_to :government_entity (optional, cross-ref)
  └── has_object :enricher

BusinessEstablishment (ODBiz: NAICS codes, addresses, employee ranges)
  ├── links to CorporateEntity via business_number
  └── belongs_to :standardized_address (optional)

StandardizedAddress (ODA: 10M geocoded addresses)
```

## Shared Concerns
- `CorporateNormalization` — name/status normalization, province mapping, batch_upsert!
- `ProvincialScraping` — rate limiting (2s delay), User-Agent, progress tracking

## Key gems
- `active_record-associated_object` — pipeline logic as associated objects
- `active_job-performs` — auto-generates job classes from methods
- `anthropic` — Claude API for entity resolution and NL queries
- `aws-sdk-s3` — R2 storage
- `nokogiri` — XML SAX parsing for ISED federal data
- `rubyzip` — ZIP extraction for ISED, Quebec, ODBiz data
- `mechanize` — form-based HTML scraping for provincial registries

## Entity resolution cascade
1. Exact match on government_entity_aliases
2. Case-insensitive match
3. Encoding normalization (curly quotes → straight)
4. LLM fuzzy match (Claude Haiku, top 5 candidates)
5. Confidence gate (>= 0.8 auto-accept, < 0.8 flag for review)

## Environment variables
- `DATABASE_URL` — Supabase Postgres connection
- `ANTHROPIC_API_KEY` — Claude API for entity resolution + NL queries
- `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `R2_ENDPOINT`, `R2_BUCKET` — Cloudflare R2
