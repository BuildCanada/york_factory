# Operational Metrics and KPIs

How Build Canada measures social and newsletter reach, what our headline number means,
and which tables in this repo are authoritative for it.

This document is the definition of record. If a number in a deck, a donor update, or a
board paper disagrees with this document, this document is what needs changing first.

- [Two metrics, not one](#two-metrics-not-one)
- [Unique reach](#unique-reach)
- [Q3 target](#q3-target)
- [Where the numbers come from](#where-the-numbers-come-from)
- [Platform primitives reference](#platform-primitives-reference)
- [Known limitations](#known-limitations)
- [Operational notes](#operational-notes)

## Two metrics, not one

Reporting needs a volume figure and a distinct-people figure. Treating one as the other is
where the current confusion comes from, so they are named and defined separately here.

1. **Content Views**, a volume measure. The number of times Build Canada content was placed
   on a screen, summed across channels, where repeat exposure to the same person counts every
   time. This is what today's dashboards report and what the [Q3 target](#q3-target) is set
   against.
2. **Unique reach**, a distinct-people measure. Defined below, deduplicated by the platform.
   Nothing computes it yet and no target is set against it.

These are different units and their magnitudes differ substantially: a reach figure for a
given period is always materially lower than a views figure for the same period. Do not
compare one to the other, and do not restate a target expressed in one as though it applied
to the other.

The word "impressions" is avoided as a headline label because it implies a single
platform-standard unit that does not exist across our channels. See
[Related](#related) for the full audit of the volume metric, including its per-channel
thresholds and known defects.

## Unique reach

**Unique reach** is the number of distinct people who saw our content, counted once per
platform per reporting window.

We measure it with platform-reported *reach* wherever a platform gives us reach, because
reach is already deduplicated by account. We fall back to gross impressions only where no
reach figure exists, and we label that fallback wherever the number is published.

```
unique_reach =
    SUM(reach)                                  -- per-post reach, deduplicated by the platform
  + linkedin.unique_impressions_organic          -- LinkedIn's own unique figure (organic only)
  + [fallback: gross impressions or views]       -- only where no reach is reported
```

### What is deduplicated, and what is not

Deduplicated:

1. Repeat views by the same person on the same platform inside the reporting window, because
   the platform does this for us before it reports reach.
2. Repeat ingestion of the same observation. Every write path is idempotent, keyed on
   `(record, date)` or `(record, observed_at)`, so re-running a sync does not inflate totals.

Not deduplicated:

1. **The same person on more than one platform.** Someone who follows us on X and LinkedIn
   counts twice. We have no cross-platform identity graph and are not planning one, so even
   this figure overstates distinct humans reached by an unmeasured margin.
2. **The same person across reporting windows.** A weekly reach figure deduplicates within
   that week; summing 13 weeks counts a loyal weekly reader up to 13 times. A cumulative
   unique reach total is therefore exposure-weighted, not person-weighted, and "unique" holds
   only within a single window.

Both limits are structural, not bugs. State them when the number goes in front of funders
or the board.

### Why reach and not impressions

Gross impressions count every render, so a single person scrolling past a post four times
contributes four. That inflates the number in a way that scales with posting frequency
rather than with audience growth, which makes it a poor measure of whether we are reaching
more Canadians. Reach moves only when the audience does.

The cost of choosing reach is coverage. Three of our channels report neither impressions nor
reach, only views, so the fallback clause carries real weight today. See
[Known limitations](#known-limitations).

## Q3 target

**17,000,000 Content Views, measured cumulatively from March 1, 2026.**

The target is set against Content Views, the volume metric, not against unique reach. This
matters: restating 17M as a reach target would compare two different units and make the number
unreachable by construction.

The figure is a running total from March 1 rather than a per-quarter reset, so progress never
resets to zero mid-year. Quarter boundaries follow the standard calendar (Q3 = July 1 to
September 30) and are not offset to a fiscal year. A `WHERE date >= '2026-03-01'` floor on a
tile labelled "Q3" is therefore correct even though the label reads as quarter-only.

Progress is reviewed weekly in the sprint deck against the Cumulative-to-Targets dashboard.

### The target spans channels this repo does not hold

Content Views is assembled across more channels than the tables documented here. Website
pageviews come from PostHog, and paid social comes from Meta Ads; neither is in York Factory
Postgres. This document is authoritative for the social and newsletter channel tables and for
the unique reach definition. It is not a complete accounting of the headline figure, and
reconciling to 17M requires the out-of-repo channels too.

## Where the numbers come from

### Current state

Every channel below is a manual export that somebody uploads or types in. Nothing in the
reported path is automated yet.

| Channel | Table | Cadence | How it gets in |
|---|---|---|---|
| X (Build Canada) | `metrics_twitter_stats` | daily | CSV upload, admin |
| X (Canada Spends) | `metrics_twitter_stats` | daily | CSV upload, admin |
| LinkedIn | `metrics_linkedin_stats` | daily | XLS upload, admin |
| TikTok | `metrics_tiktok_stats` | daily | CSV or ZIP upload, admin |
| Substack | `metrics_substack_stats` | daily | CSV upload, admin |
| Instagram | `metrics_instagram_stats` | weekly, Monday start | typed by hand, admin form |

`/admin/metrics` is the upload surface and shows the most recent date held for each channel,
which is the fastest way to spot a stale feed.

Separately, `Metrics::ScrapeZernioSocialMediaJob` runs hourly at minute 15 in production and
writes nine `metrics_social_media_*` tables. **No dashboard, API, or SQL view reads those
tables yet.** They are being populated ahead of the migration described below.

### Target state

Two tiers, split by how much a timing error would cost us:

1. **X and Instagram: direct platform API.** These are our two largest channels, so a lag or
   a window misalignment against daily reporting produces a large day-over-day swing in the
   headline number. Pulling them directly keeps the reporting window under our control.
2. **LinkedIn and TikTok: Zernio.** Smaller contributors where a modest attribution or timing
   error does not move the total materially, so the integration cost of a direct API is not
   worth paying.
3. **Substack: manual CSV, unchanged.** Zernio does not cover Substack. This is visible in the
   schema: migration `20260810180000` adds the `social_media_account` reference to the X,
   LinkedIn, TikTok, and Instagram tables only, and `Metrics::SubstackStat` is the one stat
   model with no `social_media_account` association.

Consequence worth holding onto: the Zernio scraper requests `source: "all"` and will keep
ingesting X and Instagram posts even after those channels move to direct APIs. That data is a
**cross-check, not a reported figure.** Summing Zernio X reach alongside direct-API X reach
would double count the channel.

### Gap between current and target

| Piece | Status |
|---|---|
| Zernio ingestion into Postgres | built, running hourly |
| Any read path off the Zernio tables | not built |
| X direct API | not built |
| Instagram direct API | not built |
| Reach-based unique impressions rollup | not built; no query computes the formula above |
| Retiring the manual uploads | blocked on all of the above |

## Platform primitives reference

Platforms do not agree on what they report, which is why the definition above needs a
fallback clause. Exact columns, as built:

**X**, `metrics_twitter_stats`, daily, keyed `(account, date)`
`impressions`, `likes`, `engagements`, `bookmarks`, `shares`, `new_follows`, `unfollows`,
`replies`, `reposts`, `profile_visits`, `create_post`, `video_views`, `media_views`.
No reach, no unique figure.

**LinkedIn**, `metrics_linkedin_stats`, daily, keyed `(account, date)`
`impressions_organic`, `impressions_sponsored`, `impressions_total`,
**`unique_impressions_organic`**, and organic/sponsored/total splits of `clicks`,
`reactions`, `comments`, `reposts`, plus three `engagement_rate` columns.
This is the only unique column anywhere in the schema, and it covers organic only.

**TikTok**, `metrics_tiktok_stats`, daily, keyed `(account, date)`
`video_views`, `profile_views`, `likes`, `comments`, `shares`.
No impressions, no reach.

**Instagram**, `metrics_instagram_stats`, weekly Monday-start, keyed `(account, date)`
`views`, `interactions`, `new_followers`.
No impressions, no reach. `date` is validated to be a Monday; `week_end` is `date + 6`.

**Substack**, `metrics_substack_stats`, daily, keyed `(account, date)`
`views` only.

**Zernio per post**, `metrics_social_media_post_metric_snapshots`, hourly, keyed
`(social_media_post_id, observed_at)`
`impressions`, **`reach`**, `likes`, `comments`, `shares`, `saves`, `clicks`, `views`,
`follows`, `reels_average_watch_time`, `reels_total_watch_time`, `video_duration_seconds`,
`engagement_rate`, plus the raw `source_payload`.
This is the only source of per-post reach, and the reason the definition above is reachable
at all.

**Zernio paid**, three daily tables for ad accounts, campaigns, and ads, keyed `(owner, date)`
`spend`, `impressions`, `reach`, `clicks`, `engagements`, `conversions`, `conversion_value`,
`ctr`, `cpc`, `cpm`, `cost_per_conversion`, `roas`.
Paid reach is excluded from the headline organic figure. Report it separately.

### Reading the snapshot tables

The two Zernio snapshot tables are append-only observation logs, not current-state tables.
`observed_at` is the platform's own "last updated" timestamp and `scraped_at` is when we
fetched it. A row is written only when the values actually change, so `updated_at` works as an
incremental cursor. To get a post's latest metrics, take the row with the greatest
`observed_at` for that post; do not sum the snapshots, or you will count the same post once
per observation.

## Known limitations

Carry these into any external number.

1. **Cross-platform overlap is not removed.** Distinct-humans-reached is lower than our
   headline figure by an unmeasured margin.
2. **Cumulative totals re-count returning audience** across reporting windows.
3. **Three channels report only views.** TikTok, Instagram, and Substack give neither
   impressions nor reach, so they enter the total through the fallback clause. Views and
   reach are not the same unit, so three of our six channel feeds currently depend on
   treating them as comparable. Their share of the headline total is not measured.
4. **LinkedIn unique is organic-only.** Sponsored LinkedIn has no unique figure, so any
   sponsored contribution is gross.
5. **The Zernio tables are unread.** The formula in this document is not yet computed by
   anything; today's reported numbers still come from the manual tables.
6. **Missing metrics are stored as zero.** `Metrics::ZernioScraper::METRIC_FIELDS` coerces a
   missing value to `0` for every field except `video_duration_seconds` and
   `engagement_rate`. "The platform did not report this" and "this was genuinely zero" are
   indistinguishable once written, which biases averages downward.
7. **Snapshot growth depends on an upstream field.** `observed_at` falls back to the current
   run time when Zernio omits `lastUpdated`. On that path the hourly job writes a fresh
   snapshot row per post per run, because the uniqueness key never matches the previous row.
   Watch row counts on `metrics_social_media_post_metric_snapshots`.
8. **Paid and organic must not be added together** without saying so.

## Operational notes

**Schedules**, all defined in `config/recurring.yml`, production only:

| Job | Schedule | Effect |
|---|---|---|
| `Metrics::ScrapeZernioSocialMediaJob` | hourly at minute 15 | refreshes all nine `metrics_social_media_*` tables |
| `CreateInstagramWeeksJob` | Mondays 06:00 | creates blank Instagram week rows for manual entry |

Instagram rows arrive empty and are excluded from reporting until filled;
`Metrics::InstagramStat.filled` is the scope that enforces this, requiring `views`,
`interactions`, and `new_followers` to all be present.

**Manual run:** `bin/rails feed:scrape_zernio` performs the Zernio sync inline.

**Credentials:** the Zernio job reads `ENV["ZERNIO_API_KEY"]`, falling back to
`Rails.application.credentials.dig(:zernio, :api_key)`. The key is not listed in
`.kamal/secrets` or the `env.secret` block of `config/deploy.yml`, so production depends on it
being present in encrypted credentials. When it is missing the job logs
`[Zernio] API key is not configured` and returns without raising, so a silent hourly no-op is
the failure mode to check for first.

**Error handling is asymmetric.** The job declares
`retry_on Metrics::ZernioClient::Error, attempts: 5`, but the four ad-sync methods in
`Metrics::ZernioScraper` rescue that error internally and only log a warning. Account and post
failures retry; ad failures are swallowed and skipped, so a Zernio ads outage looks like a
clean run.

**Adding a channel:** create the table with a `(account, date)` unique index, add the model
under `app/models/metrics/` with `ACCOUNTS` and `METRIC_COLUMNS`, register it in
`Admin::Metrics::OverviewController` so its freshness shows on `/admin/metrics`, and record
here which primitive it reports and whether it offers reach. A channel that reports only views
needs a note in [Known limitations](#known-limitations).

## Related

- **Impressions Ledger**, the companion audit of the Content Views volume metric. It records
  each channel's per-platform counting threshold, what is exported but deliberately excluded
  (LinkedIn sponsored impressions, YouTube), and six defects found while verifying the PostHog
  views, including website history being silently truncated at 30 days and a materialized view
  whose refresh is failing. Read it before quoting a Content Views figure. Held by Macoy;
  not yet in this repo.
- `docs/kpis/architecture.md`, the separate government-KPI platform. Unrelated to this
  document despite the shared word.
- PostHog holds the dashboards used in the weekly sprint deck (Impressions, and
  Cumulative-to-Targets). Those views are configured in the PostHog UI and are not defined in
  this repo, so they are not version controlled. PostHog usage inside this codebase is product
  event capture and Yabeda application metrics export only, which is a separate concern from
  the metrics described here.
