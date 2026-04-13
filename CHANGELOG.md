# Changelog

All notable changes to York Factory will be documented in this file.

## [0.1.3.0] - 2026-04-12

### Added

- Geographic boundary system: 13 boundary types (DA, CT, CSD, FSA, FED, PED, ward, school board ward, PR, CD, ER, CMA, PopCtr)
- Population-weighted crosswalk engine: maps between any two boundary types using DA populations as weights
- Elections Canada 2023 Representation Order FED boundaries (343 ridings) with EPSG:3347→WGS84 reprojection
- Open Database of Addresses loader for Canadian address geocoding
- Spatial crosswalks via PostGIS centroid-in-polygon for FED and PED boundaries
- Geo API endpoints: boundaries search, address search with trigram indexes, crosswalk lookups
- Toronto ward and school board ward boundaries (TDSB, TCDSB, Viamonde, MonAvenir)
- Provincial electoral district boundaries for Ontario, Alberta, and BC
- Full geo pipeline rake task (`geo:pipeline`) for end-to-end data loading
- 35 new tests for all loaders (boundary, population, relationship, address) and crosswalk computation

### Changed

- Replaced StatsCan 2021 Census FED source (338 ridings) with Elections Canada 2023 Representation Order (343 ridings)
- Crosswalk SQL queries use parameterized queries via `sanitize_sql_array` instead of string interpolation
- Population loader uses bulk `UPDATE FROM VALUES` instead of N+1 individual UPDATEs
- Crosswalk build wrapped in database transaction for atomic updates
- Extracted shared `crosswalk_query` method eliminating 3x SQL duplication in geo.rake
- Boundary loader uses EPSG SRID constants instead of hardcoded proj4 strings

## [0.1.2.0] - 2026-03-30

### Added

- Full CMS API with i18n support (English/French) via Mobility column backend
- 10 CMS models: Posts, Memos, Builders, TeamMembers, Tools, FAQs, FeedItems, Testimonials, Subscribers, Users
- ActionText with locale-aware rich text (HasLocalizedRichText concern) and Lexxy editor
- JWT authentication via Devise + Google OAuth for admin API access
- Admin interface with sidebar layout, session auth, and CMS management views
- API v1 endpoints for all CMS resources with slug-based routing, pagination (Pagy), and bulk update support
- Automatic translation pipeline: TranslateRecordJob using RubyLLM for EN→FR translation
- Publishable concern with draft/published states and scheduled publishing
- FriendlyId slug generation with history for memos, posts, and builders
- Webflow sync service and background job for content migration
- ActiveStorage with Cloudflare R2 for image uploads in production
- Rack::Attack rate limiting for API endpoints
- 18 database migrations for CMS tables, ActiveStorage, Devise, ActionText, and Mobility restructuring
- CMS seed task for development data
- 172 tests covering models, controllers, concerns, services, and API endpoints

### Fixed

- JWT secret mismatch between token creation and validation when DEVISE_JWT_SECRET_KEY is set
- Non-admin users could bypass authorization (render_forbidden didn't halt execution)
- Session fixation vulnerability on admin login (now resets session before setting user)
- URI parameter encoding in Google OAuth token verification
- ILIKE wildcard injection in admin subscriber search
- Race condition in User.from_google for concurrent first-login (handles RecordNotUnique)
- Seed task passing wrong arguments to TranslateRecordJob
- LLM translation output now validated for blank/length before writing to database

### Changed

- Replaced `anthropic` gem with `ruby_llm` for entity resolution (unified LLM interface)
- Updated admin layout from top-nav to sidebar with Pipeline and CMS sections

### Removed

- LlmClient service (replaced by direct RubyLLM calls in EntityResolver)
- Natural language query interface (deferred to future release)

## [0.1.0.0] - 2026-03-23

### Added

- Rails 8 API with Solid Queue (Postgres-backed jobs, no Redis needed)
- Full Postgres schema: organizations, fiscal authorities, fiscal expenditures, standard object expenditures, lobbying registry, lineage tracking
- InfoBase Loader: deterministic ETL for Public Accounts data (authorities + expenditures)
- Estimates Normalizer: LLM-powered entity resolution for Main Estimates
- Entity resolution cascade: exact match, case-insensitive, encoding normalization, LLM fuzzy match with confidence gate
- Organizations flagged for human review when auto-created from unmatched entities
- spending_deviations SQL VIEW: joins planned vs actual spending with variance calculation
- Natural language query interface (grounded-only, SQL generation via Claude)
- Admin dashboard for organizations, fiscal data, and spending deviations
- Mission Control dashboard for Solid Queue job monitoring
- Real data seeding tasks: `data:seed`, `data:seed_infobase`, `data:seed_estimates`
- R2 storage service for raw CSV archival (Cloudflare R2, S3-compatible)
- Kamal deployment config for OVH VPS
- 23 tests covering pipeline logic, entity resolution, and NL query safety
