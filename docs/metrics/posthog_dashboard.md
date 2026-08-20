# PostHog social analytics dashboard

`docs/metrics/README.md` notes that the PostHog dashboards behind the weekly sprint deck
are configured in the PostHog UI and are therefore not version controlled. This file is
the version-controlled definition of the social dashboard, so a rebuilt or re-pointed
dashboard produces the same numbers.

**Prerequisite:** the warehouse source from `social_analytics.md` must exist, syncing
`metrics_social_entities` and `metrics_social_metric_observations`. Table names below
assume prefix `york`.

## Build the normalizing view first

Every grain problem in these tables is solved once, here, rather than in eight tiles.
`reporting_source` spans two grains — `account_day` rows are per-day increments, while
`content_snapshot` rows are lifetime-to-date totals for one post — so this view converts
both into a single daily increment.

```sql
-- Saved warehouse view: social_content_views_daily
WITH per_period AS (
  SELECT toDate(period_start) AS day, platform, account_key, value
  FROM york_metrics_social_metric_observations
  WHERE active AND reporting_source AND NOT paid AND NOT cumulative
    AND metric_name = 'content_views'
    AND grain = 'account_day'
),
snapshots AS (
  SELECT
    platform,
    account_key,
    observed_at,
    value,
    lagInFrame(value) OVER (
      PARTITION BY social_entity_id ORDER BY observed_at
      ROWS BETWEEN 1 PRECEDING AND CURRENT ROW
    ) AS previous_value
  FROM york_metrics_social_metric_observations
  WHERE active AND reporting_source AND NOT paid AND cumulative
    AND metric_name = 'content_views'
    AND grain = 'content_snapshot'
),
per_content AS (
  -- greatest(..., 0) guards against a platform revising a lifetime count down.
  SELECT toDate(observed_at) AS day, platform, account_key,
         greatest(value - coalesce(previous_value, 0), 0) AS value
  FROM snapshots
)
SELECT day, platform, account_key, sum(value) AS content_views
FROM (SELECT * FROM per_period UNION ALL SELECT * FROM per_content)
GROUP BY day, platform, account_key
```

This supersedes `queries/content_views.sql`, which answers the same question for one fixed
window. Prefer the view: daily increments make every tile a plain aggregation, and the Q3
figure becomes a cumulative sum rather than a bespoke baseline subtraction.

**Known distortion.** A post's first snapshot has no predecessor, so its entire
lifetime-to-date count lands on that one day. For content published before Zernio
ingestion began, that dumps historical views onto the ingestion start date as a spike.
Establish that date once and exclude it, or start the window after it:

```sql
SELECT platform, min(observed_at) FROM york_metrics_social_metric_observations
WHERE cumulative AND reporting_source AND metric_name = 'content_views' GROUP BY platform
```

## Tiles

### 1. Q3 Content Views vs target — big number
Target is 17,000,000 cumulative from 2026-03-01 (`README.md`). Social only; see caveats.
```sql
SELECT sum(content_views) FROM social_content_views_daily WHERE day >= '2026-03-01'
```

### 2. Cumulative Content Views vs target — line
```sql
SELECT day, sum(sum(content_views)) OVER (ORDER BY day) AS cumulative
FROM social_content_views_daily WHERE day >= '2026-03-01' GROUP BY day ORDER BY day
```
Add a 17,000,000 goal line.

### 3. Weekly Content Views by channel — stacked bar
```sql
SELECT toStartOfWeek(day) AS week, platform, sum(content_views) AS views
FROM social_content_views_daily WHERE day >= '2026-03-01'
GROUP BY week, platform ORDER BY week
```

### 4. Channel mix — bar
Same as tile 3 without the week grouping. Answers "which channels actually carry the
number", which decides where effort goes.

### 5. Followers by platform — table
Per `social_analytics.md`, Zernio account snapshots are the reporting source for followers
on every platform.
```sql
SELECT platform, account_key, argMax(value, observed_at) AS followers
FROM york_metrics_social_metric_observations
WHERE active AND reporting_source AND metric_name = 'followers'
GROUP BY platform, account_key ORDER BY followers DESC
```

### 6. Unique reach — table, Instagram only
Label it explicitly. Instagram (`meta_api`) is currently the only reporting source for
`unique_reach`; LinkedIn's `unique_impressions_organic` is ingested but not reportable.
Never present this next to tile 1 as though they were comparable units.
```sql
SELECT toStartOfWeek(period_start) AS week, platform, sum(value) AS unique_reach
FROM york_metrics_social_metric_observations
WHERE active AND reporting_source AND NOT paid AND metric_name = 'unique_reach'
GROUP BY week, platform ORDER BY week
```

### 7. Feed freshness — table
Replicates what `/admin/metrics` shows, and catches the silent failure modes: a Zernio
no-op from a missing API key, an expired Substack cookie, unfilled Instagram weeks.
```sql
SELECT source, platform, max(period_start) AS latest_data, max(refreshed_at) AS last_rebuild
FROM york_metrics_social_metric_observations
WHERE active GROUP BY source, platform ORDER BY latest_data
```

### 8. Fallback-metric share — big number
`README.md` limitation #3 records that the share of the headline total depending on the
views-as-reach fallback "is not measured". This measures it.
```sql
SELECT
  sum(value) FILTER (WHERE fallback_metric) / nullif(sum(value), 0) AS fallback_share
FROM york_metrics_social_metric_observations
WHERE active AND reporting_source AND NOT paid AND day >= '2026-03-01'
```

### 9. Paid performance — separate table
Never in the same tile as organic (`README.md` limitation #8).
```sql
SELECT platform, account_key, metric_name, sum(value)
FROM york_metrics_social_metric_observations
WHERE active AND reporting_source AND paid AND grain = 'entity_day'
  AND metric_name IN ('spend', 'impressions', 'reach', 'clicks', 'conversions')
GROUP BY platform, account_key, metric_name
```

## What this dashboard is not

It is **social channels only**. Reconciling to 17M also needs website pageviews (PostHog
events, already in the project) and paid social (Meta Ads, not in Postgres). Once the
warehouse source exists both live in the same project, so a combined tile is finally
possible — that is the reconciliation `README.md` says cannot be done today.

Facebook is ingested but `reporting_source` is false for it everywhere, so it contributes
nothing to any tile here.
