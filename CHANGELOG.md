# Changelog

All notable changes to York Factory will be documented in this file.

## [0.1.1.0] - 2026-03-26

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
- 116 tests covering models, controllers, concerns, and services

### Changed

- Replaced `anthropic` gem with `ruby_llm` for entity resolution (unified LLM interface)
- Updated admin layout from top-nav to sidebar with Pipeline and CMS sections
- Added i18n configuration (en/fr locales) and ActionDispatch::Flash middleware
- Added CORS configuration for API endpoints
- Added R2 storage service configuration
- Added solid_cache database connection for dev/prod environments

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
