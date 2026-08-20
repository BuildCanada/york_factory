# Handoff: PostHog social analytics source + dashboard

Transient task spec. Delete when done. Written 2026-08-20.

## Objective

Get Build Canada's social metrics out of Postgres and into PostHog, then build a dashboard
over them. Two deliverables:

1. A PostHog data warehouse source syncing two tables from Supabase Postgres.
2. A dashboard with 9 tiles, already specified in `docs/metrics/posthog_dashboard.md`.

Requested by Mikaal's boss (Brendan Samek, `xrendan`, who wrote the PR that created these
tables): "For posthog, you need to add some tables to the incremental sync in the data
warehouse part."

## Read these first

| File | Why |
|---|---|
| `docs/metrics/social_analytics.md` | Definition of record for the two tables. Read fully. |
| `docs/metrics/posthog_dashboard.md` | The dashboard spec you are implementing. Tile queries included. |
| `docs/metrics/README.md` | Metric definitions, the 17M Q3 target, 8 known limitations. |
| `docs/metrics/queries/content_views.sql` | Single-window roll-up. Superseded by the view in the dashboard spec; keep for reference. |
| `app/services/metrics/social_analytics_refresh.rb` | Builds both tables. Read `persist!`. |

## Current state

**Nothing exists in PostHog yet.** No source, no view, no dashboard. Everything below is
unstarted.

- PostHog org is on **US cloud** — `us.posthog.com`. Not EU.
- The two target tables are populated in production by
  `Metrics::RefreshSocialAnalyticsJob`, every 6 hours at minute 45 (`config/recurring.yml`).
- PR #107 (https://github.com/BuildCanada/york_factory/pull/107) is **open, not merged**.
  It fixes the incremental cursor. See "Sync frequency" below — this gates a config choice.
- `docs/metrics/posthog_dashboard.md` is **untracked**. Decide with Mikaal whether it goes
  onto #107 or its own PR.
- Working branch: `fix/social-analytics-incremental-cursor`.

## Blockers — both need Mikaal, neither is yours to solve

### 1. PostHog MCP authentication

OAuth is broken. Two attempts against `oauth.posthog.com/oauth/authorize` returned
**upstream request timeout**. All four PostHog hosts respond in ~100ms, so it is not an
outage; the likely cause is the ~150-scope grant the MCP server requests. Do not retry it.

The fallback is already wired: a user-scope MCP entry named **`posthog-direct`** exists in
`~/.claude.json`, pointing at `https://mcp.posthog.com/mcp` with
`Authorization: Bearer ${POSTHOG_PERSONAL_API_KEY}`. It currently 401s because the variable
is unset.

Mikaal must create a personal API key at `us.posthog.com/settings/user-api-keys` with scopes
`external_data_source:write`, `warehouse_table:read`, `warehouse_view:write`,
`insight:write`, `dashboard:write`, `query:read`, `project:read`; export
`POSTHOG_PERSONAL_API_KEY` in `~/.zshrc`; and restart Claude Code. Headers resolve from the
process environment at startup, so a restart is mandatory.

Note: setting an `Authorization` header disables OAuth fallback on that entry. That is
intended.

### 2. Supabase read-only role

DDL on production. Mikaal runs this, not you:

```sql
CREATE ROLE posthog_reader LOGIN PASSWORD '<long random>';
GRANT USAGE ON SCHEMA public TO posthog_reader;
GRANT SELECT ON public.metrics_social_entities,
                 public.metrics_social_metric_observations
  TO posthog_reader;
```

**Why this matters and is not optional.** The two target tables live in `public` alongside
53 others, including `users`, `subscribers`, and `saved_searches`. PostHog's one-step
warehouse setup auto-discovers and enables *every* table it finds. Running that flow with
superuser credentials would replicate subscriber PII into PostHog as a side effect. The role
makes that structurally impossible instead of dependent on getting a table picker right.

## Execution

### Step 1 — Create the source

Use the **hand-pick flow**, not `data-warehouse-source-setup`. The one-step tool enables all
discovered tables; see above for why that is unacceptable here.

Collect credentials via `data-warehouse-source-connect-link` — never take the database
password in chat.

Connection details. **The session pooler is mandatory**; the direct host
(`db.<ref>.supabase.co`) is IPv6-only and fails validation:

| Field | Value |
|---|---|
| Host | `aws-0-<region>.pooler.supabase.com` |
| Port | `6543` |
| Database | `postgres` |
| User | `posthog_reader` |
| Schema | `public` |
| Prefix | `york` |

If validation times out rather than returning an auth error, Supabase network restrictions
are blocking PostHog's egress IPs. Allowlist and retry.

Enable exactly two tables, everything else `should_sync: false`:

| Table | sync_type | incremental_field | primary key |
|---|---|---|---|
| `metrics_social_entities` | `incremental` | `updated_at` (datetime) | `id` (string) |
| `metrics_social_metric_observations` | `incremental` | `updated_at` (datetime) | `id` (string) |

**Sync frequency: 24h if PR #107 is unmerged; 6h is fine once it lands.** Before #107,
`persist!` rewrote `updated_at` on every row every run, so incremental sync transferred the
whole table each time while being billed per row synced. After #107, `updated_at` moves only
on real change and `refreshed_at` carries "seen this run". Do not point the cursor at
`refreshed_at` — that reintroduces the full-transfer behaviour.

### Step 2 — Create the normalizing view

Copy the `social_content_views_daily` definition verbatim from
`docs/metrics/posthog_dashboard.md`. Build it before any tile.

This view is the whole point. `reporting_source = true` spans two grains that are different
units — `account_day` rows (X, Substack, Instagram) are per-day increments, while
`content_snapshot` rows (LinkedIn, TikTok) are lifetime-to-date totals for a single post.
The view converts both to daily increments so tiles become plain aggregations.

Expect to adjust ClickHouse function names on first run (`lagInFrame`, the
`FILTER (WHERE ...)` in tile 8). **None of the queries in the spec have ever been executed** —
no warehouse source existed to run them against. Validate each before wiring it to a tile.

### Step 3 — Build the 9 tiles

Follow `docs/metrics/posthog_dashboard.md`. Two layout constraints from `README.md` that are
correctness issues, not aesthetics:

- **Tile 6 (unique reach) must not sit adjacent to tile 1 (Content Views).** Different units.
  Only Instagram reports unique reach today. Adjacency invites restating the 17M volume
  target as a reach target, which the docs exist to prevent.
- **Tile 9 (paid) must never share a tile with organic.** Limitation #8.

### Step 4 — Verify before declaring done

Run the ingestion-start check from the dashboard spec:

```sql
SELECT platform, min(observed_at) FROM york_metrics_social_metric_observations
WHERE cumulative AND reporting_source AND metric_name = 'content_views' GROUP BY platform
```

A post's first snapshot has no predecessor, so its entire lifetime-to-date count lands on
that one day. For content published before Zernio ingestion began, that dumps history onto
the ingestion start date as a spike, **inflating** totals. Establish the date, then exclude
it or start the window after it. Report the number to Mikaal either way.

Also confirm the `grain` mix is what you expect:

```sql
SELECT platform, grain, count(*) FROM york_metrics_social_metric_observations
WHERE active AND reporting_source AND NOT paid AND metric_name = 'content_views'
GROUP BY platform, grain
```

You should see `account_day` for X/Substack/Instagram and `content_snapshot` for
LinkedIn/TikTok. Anything else means the tier assignments changed and the view needs review.

## Traps

- **Facebook is ingested but `reporting_source` is false for it everywhere**, so it
  contributes to no tile. Believed deliberate per the tier list in `social_analytics.md`.
  There is an open question to `@xrendan` on PR #107. Do not "fix" this by flipping the flag.
- **`unique_reach` is Instagram-only.** LinkedIn's `unique_impressions_organic` is ingested
  but not a reporting source.
- **Never sum paid and organic.** Filter `paid` explicitly, always.
- **This dashboard is social channels only.** Website pageviews (PostHog events, already in
  the project) and paid social (Meta Ads, not in Postgres) are excluded. Reconciling to the
  17M target needs both. Once the warehouse source exists they are queryable in the same
  project for the first time — a combined tile is the natural follow-up and is the
  reconciliation `README.md` says is currently impossible.

## Out of scope, but do not lose

- **Subscriber emails are pushed to Substack every 10 minutes with no consent or unsubscribe
  gate.** `SyncSubstackSubscribersJob` + `SubstackSubscriberImporter`, scheduled in
  `config/recurring.yml`. The scope is `Subscriber.not_synced_to_substack`, which is only
  `substack_synced_at: nil` — and the `subscribers` table has no unsubscribe column at all,
  so every address ever collected is in scope. Auth is a session cookie against Substack's
  undocumented private API; on expiry the job silently no-ops. Mitigation present:
  `sendEmails: false`.

  This shipped in PR #101 undescribed, inside a PR about analytics ingestion. It has no
  owner and is tracked nowhere. Not a patch — it needs whoever owns subscriber consent.
  Raise it; do not quietly fix or ignore it.

- **`SocialAnalyticsRefresh` loads all history into memory** before persisting — 13
  observations per Zernio post snapshot, 21 per Substack snapshot, and per limitation #7 in
  `README.md` the snapshot table can grow a row per post per hour. PR #107 chunks the write
  at 1,000 rows but does not touch the accumulation. Expect this to OOM eventually.

- **`mark_current_values` groups by `[entity, source, metric_name]`**, ignoring
  `source_metric_name`. `META_CONTENT_METRICS` maps both `views` and `post_media_view` to
  `content_views`; if a platform ever returned both, one would silently lose `current_value`.
  Latent, not firing today.
