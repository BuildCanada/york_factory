# Changelog

All notable changes to York Factory will be documented in this file.

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
