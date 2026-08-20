-- Canonical Content Views roll-up (HogQL, against the PostHog warehouse source).
--
-- Table names assume the warehouse source was created with prefix `york`; swap
-- the prefix if it was created with another. The `york_` tables are the synced
-- copies of metrics_social_metric_observations described in
-- docs/metrics/social_analytics.md.
--
-- Before trusting the total, confirm snapshot history reaches back past the
-- window start. If Zernio ingestion began after 2026-03-01 the `baseline` CTE
-- is empty, and every pre-window post's full lifetime count lands inside the
-- window — inflating the figure rather than undercounting it:
--
--   SELECT platform, min(observed_at)
--   FROM york_metrics_social_metric_observations
--   WHERE cumulative AND reporting_source AND metric_name = 'content_views'
--   GROUP BY platform
--
-- Why this is not a plain SUM
-- ---------------------------
-- `reporting_source = true` spans two different grains, and they are different
-- units:
--
--   X, Substack, Instagram   grain = account_day        cumulative = false
--                            value = views that occurred on that day
--
--   LinkedIn, TikTok         grain = content_snapshot   cumulative = true
--                            value = lifetime-to-date views of one post
--
-- Two traps follow:
--
--   1. SUM(value) across both mixes daily increments with lifetime totals.
--   2. Content rows set period_start = the post's published_at, so filtering
--      period_start >= <window> asks "posts PUBLISHED in the window" for
--      LinkedIn/TikTok but "views that OCCURRED in the window" for the others.
--      A February LinkedIn post accruing views in August is silently dropped.
--
-- For cumulative rows the window axis must be `observed_at`, and the in-window
-- value is (latest snapshot - the last snapshot before the window opened).
-- Posts first seen inside the window have no baseline, so their baseline is 0.
--
-- Older snapshots stay queryable (active = true, current_value = false), which
-- is what makes the baseline recoverable.
--
-- Q3 target per docs/metrics/README.md: 17,000,000 cumulative from 2026-03-01.

WITH
  toDateTime('2026-03-01 00:00:00') AS window_start,

  -- Per-period channels: value is already an in-window increment.
  per_period AS (
    SELECT
      platform,
      account_key,
      sum(value) AS content_views
    FROM york_metrics_social_metric_observations
    WHERE active
      AND reporting_source
      AND NOT paid
      AND NOT cumulative
      AND metric_name = 'content_views'
      AND grain IN ('account_day', 'account_week')
      AND period_start >= window_start
    GROUP BY platform, account_key
  ),

  -- Cumulative channels: latest lifetime value per piece of content.
  latest AS (
    SELECT
      social_entity_id,
      platform,
      account_key,
      argMax(value, observed_at) AS value
    FROM york_metrics_social_metric_observations
    WHERE active
      AND reporting_source
      AND NOT paid
      AND cumulative
      AND metric_name = 'content_views'
    GROUP BY social_entity_id, platform, account_key
  ),

  -- Lifetime value as it stood the moment the window opened.
  baseline AS (
    SELECT
      social_entity_id,
      argMax(value, observed_at) AS value
    FROM york_metrics_social_metric_observations
    WHERE active
      AND reporting_source
      AND NOT paid
      AND cumulative
      AND metric_name = 'content_views'
      AND observed_at < window_start
    GROUP BY social_entity_id
  ),

  per_content AS (
    SELECT
      latest.platform,
      latest.account_key,
      -- greatest(...,0) guards against a platform revising a lifetime count down.
      sum(greatest(latest.value - coalesce(baseline.value, 0), 0)) AS content_views
    FROM latest
    LEFT JOIN baseline ON baseline.social_entity_id = latest.social_entity_id
    GROUP BY latest.platform, latest.account_key
  )

SELECT platform, account_key, 'per_period' AS basis, content_views FROM per_period
UNION ALL
SELECT platform, account_key, 'per_content' AS basis, content_views FROM per_content
ORDER BY content_views DESC;

-- Headline single number (feeds the Cumulative-to-Targets tile):
--
--   SELECT sum(content_views) FROM ( <the UNION ALL above> )
--
-- Caveats to carry, per docs/metrics/README.md:
--   * Facebook is ingested but reporting_source = false everywhere, so it
--     contributes nothing here. Confirm that is intended.
--   * Website pageviews (PostHog events) and paid social (Meta Ads) are NOT in
--     these tables. Reconciling to 17M requires both.
--   * unique_reach is a different metric on a different unit. Today only
--     Instagram (meta_api) is a reporting source for it. Never restate the
--     17M Content Views target as a reach target.
