-- Canonical Content Views roll-up (HogQL, against the PostHog warehouse source).
--
-- This uses the PostHog source/table name configured for York Factory.
--
-- Every supported platform now has account-day observations. LinkedIn and
-- TikTok content snapshots remain reportable as cross-checks, so the grain
-- filter is essential: it prevents daily account increments from being mixed
-- with lifetime-to-date post totals.
--
-- `paid IS NOT TRUE` means "organic where the platform exposes attribution,
-- otherwise combined". Instagram has separate paid/organic rows; LinkedIn and
-- TikTok account-day endpoints currently return combined values.
--
-- Q3 target per docs/metrics/README.md: 17,000,000 cumulative from 2026-03-01.

SELECT
  platform,
  account_key,
  sum(value) AS content_views
FROM postgres.york_factory.metrics_social_metric_observations
WHERE active
  AND current_value
  AND reporting_source
  AND paid IS NOT TRUE
  AND NOT cumulative
  AND metric_name = 'content_views'
  AND grain = 'account_day'
  AND period_start >= toDateTime('2026-03-01 00:00:00')
GROUP BY platform, account_key
ORDER BY content_views DESC;

-- Headline single number (feeds the Cumulative-to-Targets tile):
--
--   SELECT sum(content_views) FROM ( <the SELECT above> )
--
-- Caveats to carry, per docs/metrics/README.md:
--   * Facebook is ingested but reporting_source = false everywhere, so it
--     contributes nothing here. Confirm that is intended.
--   * Website pageviews (PostHog events) and paid social (Meta Ads) are NOT in
--     these tables. Reconciling to 17M requires both.
--   * unique_reach is a different metric on a different unit. Today only
--     Instagram (meta_api) is a reporting source for it. Never restate the
--     17M Content Views target as a reach target.
