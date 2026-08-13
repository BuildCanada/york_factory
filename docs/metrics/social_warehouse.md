# Social analytics warehouse

PostHog reports should sync these physical tables from the `warehouse` schema:

- `social_entities`: stable accounts, content, ad accounts, campaigns, and ads.
- `social_metric_observations`: numeric facts using the same metric names across sources.

Configure PostHog incremental sync with `id` as the primary key and `updated_at` as the
cursor. Both tables are rebuilt idempotently every six hours by
`Metrics::RefreshSocialWarehouseJob`. Rows no longer present upstream remain available with
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
source for the same channel. Direct Meta content snapshots are also cross-checks: Instagram's
account-level daily insights are the reporting grain, so adding its post-level snapshots would
count the channel twice.

`content_views` is a volume measure. `unique_reach` is reserved for an account-level value
that the platform has deduplicated for its reporting window. Per-content reach is named
`content_reach`; summing it does not produce unique platform reach. `fallback_metric` marks
future reach values derived from non-unique views or impressions.

Snapshot sources set `cumulative = true`. Only their latest observation per entity, source,
and normalized metric has `current_value = true`; older snapshots remain queryable for
history without being accidentally summed into current reports.
