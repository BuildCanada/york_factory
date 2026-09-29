# York Factory — Canadian Fiscal Data Pipeline + CMS

## What is York Factory?
Automated pipeline that normalizes Canadian federal government fiscal data (Public Accounts, Main Estimates, Supplementary Estimates) into shared, queryable Postgres tables. Includes a bilingual CMS API for Build Canada's website content (posts, memos, builders, team, tools, FAQs, feed items, testimonials). Built for Build Canada's community of contributors who build government accountability tools.

## Commands
```bash
bin/rails test                    # run all tests (599 tests)
bin/rails db:migrate              # apply migrations
bin/rails db:seed                 # seed data sources
bin/rails cms:seed                # seed CMS development data
bin/rails console                 # Rails console
```

## Architecture
- **Rails 8 API** with Solid Queue (Postgres-backed jobs, no Redis)
- **Supabase** for managed Postgres (production uses DATABASE_URL)
- **Cloudflare R2** with separate buckets for archival (R2_BUCKET) and ActiveStorage (R2_ACTIVE_STORAGE_BUCKET)
- **Kamal** for deployment to OVH VPS
- **Mobility** column backend for i18n (EN/FR)
- **Markdown** (Commonmarker + reverse_markdown) with the Marksmith editor in admin; inline images stored in ActiveStorage
- **Devise + JWT** for API authentication, Google OAuth for admin

## Pipeline (associated objects pattern)
```
Source::Fetcher                   → downloads CSV/shapefile, archives to R2, creates RawIngestion
RawIngestion::InfobaseLoader      → deterministic ETL for InfoBase (Public Accounts)
RawIngestion::EstimatesNormalizer → LLM-powered entity resolution for Estimates
RawIngestion::LobbyingNormalizer  → lobbying registry normalization
RawIngestion::BoundaryLoader      → shapefile import for 13 geo boundary types (PostGIS)
RawIngestion::RelationshipLoader  → DA→parent geographic relationships from StatsCan
RawIngestion::PopulationLoader    → DA population data for crosswalk weighting
RawIngestion::AddressLoader       → Open Database of Addresses (ZIP→CSV import)
RawIngestion::IrccAdmissionsLoader → IRCC PR admissions by immigration category (monthly TSV)
RawIngestion::TorontoCandidatesLoader → Toronto election candidates into elections/races/candidates tables
RawIngestion::BramptonCandidatesLoader → Brampton election candidates (scraped candidate page) into the same tables
RawIngestion::HamiltonCandidatesLoader → Hamilton election candidates (scraped candidate page) into the same tables
Organization::EntityResolver      → shared entity resolution cascade
```

## CMS API
```
API v1: memos, posts, builders, team_members, tools, faqs, feed_items, testimonials, subscribers, uploads, elections
Admin:  session auth, CRUD for all resources, retranslate, reorder, Webflow sync
        elections/races/candidates are fully editable so regions with no scrapable
        source (Ottawa) can be entered and maintained by hand; elections are
        published_at-gated (Publishable) so a half-entered one stays off the API
```

## Developer console and API keys
```
/developers                 → overview: plan, limits, data terms, quickstart, recent activity
/developers/keys            → keys: create (shown once), detail, rename/rescope/restrict, rotate with grace, revoke
/admin/developers           → staff: accounts (plan override, suspend), all keys, audit log (CSV), Bifrost reconciliation, mass rotation
/internal/keys/lookup       → HMAC-signed key lookup for the data-edge Worker
```
Keys are `bc_live_<secret>_<crc6>`; only an HMAC digest is stored. `Keys::Issue`, `Keys::Rotate`, `Keys::Revoke` and
`Keys::Update` change keys (audited in `audit_events`, append-only); `Keys::Verify` checks a presented key, and the
`PublicApiAuthentication` concern wraps it for public API controllers. Bifrost (`BifrostClient`) is called only on
create, rotate and revoke, and is faked in tests (`test/support/fake_bifrost.rb`).

## Geo API
```
GET /api/v1/geo/boundaries       → search boundaries by type, province, name
GET /api/v1/geo/addresses        → search addresses by street, city, province, postal code
GET /api/v1/geo/crosswalk/:type/:uid → population-weighted crosswalk lookup
```

## Key gems
- `active_record-associated_object` — pipeline logic as associated objects
- `active_job-performs` — auto-generates job classes from methods
- `ruby_llm` — unified LLM interface for entity resolution and translations
- `aws-sdk-s3` — R2 storage
- `mobility` — i18n with column backend (title_en, title_fr)
- `devise` + `devise-jwt` — authentication
- `friendly_id` — slug generation with history
- `marksmith` + `commonmarker` + `reverse_markdown` — markdown editor, renderer, and HTML-to-markdown conversion
- `pagy` — pagination
- `rgeo` + `rgeo-proj4` + `rgeo-shapefile` — geographic data processing and coordinate reprojection
- `activerecord-postgis-adapter` — PostGIS spatial database support

## Entity resolution cascade
1. Exact match on organization_aliases
2. Case-insensitive match
3. Encoding normalization (curly quotes → straight)
4. LLM fuzzy match (Claude Haiku, top 5 candidates)
5. Confidence gate (>= 0.8 auto-accept, < 0.8 flag for review)

## Environment variables
- `DATABASE_URL` — Supabase Postgres connection
- `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `R2_ENDPOINT` — Cloudflare R2 credentials
- `R2_BUCKET` — R2 bucket for raw CSV archival (pipeline)
- `R2_ACTIVE_STORAGE_BUCKET` — R2 bucket for ActiveStorage uploads (CMS images)
- `CORS_ORIGINS` — Allowed CORS origins (comma-separated, defaults to *)
- `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET` — Google OAuth for admin
- Public data API keys (docs: fact-factory `docs/public-interface-design.md` §4). Each is an env var or a Rails credential:
  - `API_KEY_PEPPER` / `api_keys.pepper` — HMAC pepper for key digests, shared with the edge Worker. **Required in production.**
  - `API_KEY_ISSUER` / `api_keys.issuer` — `bifrost` (production default) or `local`
  - `API_KEY_PREFIX` / `api_keys.prefix` — `bc_live_` (production default) or `bc_stg_` (staging, development, test)
  - `BIFROST_URL`, `BIFROST_ADMIN_USERNAME`, `BIFROST_ADMIN_PASSWORD` / `bifrost.url`, `bifrost.admin_username`, `bifrost.admin_password` — Bifrost admin API (key create, rotate, revoke only)
  - `BIFROST_CUSTOMERS` / `bifrost.customers` — `false` to skip creating one Bifrost customer per account
  - `EDGE_URL`, `EDGE_HMAC_SECRET` / `edge.url`, `edge.hmac_secret` — the data-edge Worker; key pushes are skipped when unset
  - `PUBLIC_API_ANONYMOUS` — `false` turns off anonymous `read:public` access
- Mailer/SES config is read from Rails credentials under `mailer`:
  - `mailer.smtp_address` — SES SMTP endpoint (defaults to `email-smtp.ca-central-1.amazonaws.com`)
  - `mailer.smtp_username`, `mailer.smtp_password` — SES SMTP credentials (IAM SMTP user)
  - `mailer.host` — Host for mailer URL generation (defaults to `api.buildcanada.com`)
  - `mailer.sender` — From address for Devise emails (defaults to `no-reply@buildcanada.com`)
