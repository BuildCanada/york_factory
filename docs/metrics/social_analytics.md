# Social analytics reporting tables

Social analytics are private operational data. They live in the primary application's `public`
schema and must never be placed in the public-data-only `warehouse` schema.

PostHog reports should sync these physical tables:

- `metrics_social_entities`: stable accounts, content, ad accounts, campaigns, and ads.
- `metrics_social_metric_observations`: numeric facts using the same metric names across sources.

Configure PostHog incremental sync with `id` as the primary key and `updated_at` as the
cursor. Both tables are rebuilt idempotently every six hours by
`Metrics::RefreshSocialAnalyticsJob`. Rows no longer present upstream remain available with
`active = false`, so incremental sync does not depend on delete propagation.

For normal reports, filter observations to:

```sql
active = true
AND current_value = true
AND reporting_source = true
```

Also filter `paid` explicitly. Never add paid and organic rows without labelling the result.

`reporting_source` follows the source-of-truth tiers: X exports, direct Meta Instagram,
Zernio LinkedIn and TikTok, and Substack daily stats. Other observations are retained as
cross-checks. This prevents Zernio X or Instagram observations from being added to the direct
source for the same channel. Follower totals are the exception: Zernio account snapshots are
reportable for every configured social platform because the direct exports do not consistently
provide a comparable current follower total. Direct Meta content snapshots are also cross-checks: Instagram's
account-level daily insights are the reporting grain, so adding its post-level snapshots would
count the channel twice.

`content_views` is a volume measure. `unique_reach` is reserved for an account-level value
that the platform has deduplicated for its reporting window. Per-content reach is named
`content_reach`; summing it does not produce unique platform reach. `fallback_metric` marks
future reach values derived from non-unique views or impressions.

Snapshot sources set `cumulative = true`. Only their latest observation per entity, source,
and normalized metric has `current_value = true`; older snapshots remain queryable for
history without being accidentally summed into current reports.

## Instagram account grain

Instagram's account-level `views`, `accounts_engaged`, `total_interactions`,
`profile_links_taps` and `follows_and_unfollows` are only available from Meta as
`metric_type=total_value`. A `total_value` response aggregates over the whole
requested window and carries no `end_time`, so it must be requested one day at a
time or it cannot be attributed to a calendar day.

`Metrics::MetaAnalyticsSync` therefore requests these metrics per day with explicit
`since`/`until`, and stamps `observed_at` with the end of the requested day. That
matches Meta's own convention for time-series metrics such as `reach`, where a value
stamped Aug 12 00:00 covers Aug 11, and keeps both kinds of row on one timeline.

Day boundaries follow the account's timezone, not UTC. The default is
`America/Los_Angeles`, inferred from the `end_time` values Meta returns for `reach`
(07:00Z in August). Override with `meta.time_zone`, or per account with
`meta.accounts.<platform>.<account_key>.time_zone`.

Each sync re-requests a trailing window (`DEFAULT_SYNC_LOOKBACK_DAYS`, currently 3)
because Meta keeps revising a day's totals after midnight. Re-requests upsert on
`(meta_account_id, metric_name, period, observed_at)`.

To recover history, or days captured before this behaviour existed, use
`Metrics::BackfillMetaAccountInsightsJob` or the `meta_insights:backfill` rake task.
Rows written by the older code carry the sync clock rather than a day boundary;
`meta_insights:undated` lists them and `meta_insights:purge_undated` removes them.
Clear them before backfilling the same dates, or the two sets sum together.
