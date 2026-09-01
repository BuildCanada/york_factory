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

`updated_at` moves only when a row's values actually change, including the flip to
`active = false`. `refreshed_at` is the separate "this run saw the row" stamp, and is not
part of the change comparison. A rebuild that finds nothing new therefore advances no
cursor and syncs no rows; do not treat `refreshed_at` as the incremental cursor or every
sync becomes a full table transfer.

For normal reports, filter observations to:

```sql
active = true
AND current_value = true
AND reporting_source = true
```

Also filter `paid` explicitly. It is tri-state: `true` is paid, `false` is organic,
and `NULL` is a combined value that the source cannot split correctly. Never add
paid, organic, and combined rows without labelling the result.

`reporting_source` follows the source-of-truth tiers: X exports, direct Meta Instagram,
Zernio LinkedIn and TikTok, and Substack daily stats. Other observations are retained as
cross-checks. This prevents Zernio X or Instagram observations from being added to the direct
source for the same channel. Follower totals are the exception: Zernio account snapshots are
reportable for every configured social platform because the direct exports do not consistently
provide a comparable current follower total. Direct Meta content snapshots are also cross-checks: Instagram's
account-level daily insights are the reporting grain, so adding its post-level snapshots would
count the channel twice.

`reporting_source` alone does not make the rows summable. LinkedIn and TikTok now have
both per-day account observations and lifetime-to-date content snapshots. Both remain
reportable because the snapshots are useful cross-checks, but they must not be added
together. For a daily downstream series, filter `grain = 'account_day'`. Content rows
set `period_start` to the content's publication time and should only be used when the
question is specifically about content-level performance.

Zernio account-day collection uses platform-specific APIs. LinkedIn is read from the
organization aggregate time series in bounded windows; its `until` date is exclusive.
TikTok is read from daily metrics with `source = all` and `attribution = received`.
Both APIs omit inactive dates, so the scraper stores explicit zero rows for newly
encountered missing dates from the first observed day onward. A later sparse response
does not erase a previously stored day or field; explicit values returned for that
day still capture upstream revisions. The initial run requests one year of history
and later runs re-request a trailing seven days.

LinkedIn and TikTok account-level view totals do not expose a reliable paid/organic
split through these endpoints, so those observations carry `paid = NULL` (combined).
Instagram publishes separate organic and paid account-day views. Queries for organic
views with a combined fallback should use `paid IS NOT TRUE`: that selects organic rows
where the platform provides the split and combined rows where it does not.

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
`since`/`until`, with `until` set one second before the next midnight because Meta
treats an epoch timestamp exactly at midnight as inclusive. It stamps `observed_at`
with the end of the requested day. That
matches Meta's own convention for time-series metrics such as `reach`, where a value
stamped Aug 12 00:00 covers Aug 11, and keeps both kinds of row on one timeline.

Instagram `views` and `total_interactions` are requested with the
`media_product_type` breakdown. Meta identifies paid delivery as `AD`; the remaining
media product values are normalized as organic. Reporting observations publish the
two components separately with `paid = true` and `paid = false`. The raw combined
total remains in `metrics_meta_account_insights` for auditing, but is not published as
a third reporting observation that could be double-counted. `follows_and_unfollows`
is similarly unpacked into `followers_gained` and `followers_lost`; it must not be
treated as a scalar net-follow count.

Instagram `reach` remains combined. Although Meta exposes reach by media product,
reach counts unique accounts and those product buckets overlap, so subtracting the
`AD` bucket from total reach would not produce organic unique reach. Meta also does
not support this breakdown for `accounts_engaged` or `profile_links_taps`. These
source rows remain combined rather than being assigned an invented paid or organic
value. Combined observations carry `paid = NULL`.

Day boundaries follow the account's timezone, not UTC. The default is
`America/Los_Angeles`, inferred from the `end_time` values Meta returns for `reach`
(07:00Z in August). Override with `meta.time_zone`, or per account with
`meta.accounts.<platform>.<account_key>.time_zone`.

Each sync re-requests a trailing window (`DEFAULT_SYNC_LOOKBACK_DAYS`, currently 3)
because Meta keeps revising a day's totals after midnight. Re-requests upsert on
`(meta_account_id, metric_name, period, observed_at)`.

To recover history, or days captured before this behaviour existed, use
`Metrics::BackfillMetaAccountInsightsJob` or the `meta_insights:backfill` rake task.
Timestamped time-series metrics such as `reach` are requested in bounded 30-day
ranges; total-value metrics remain one request per account day.
Rows written by the older code carry the sync clock rather than a day boundary;
`meta_insights:undated` lists them and `meta_insights:purge_undated` removes them.
Clear them before backfilling the same dates, or the two sets sum together.
