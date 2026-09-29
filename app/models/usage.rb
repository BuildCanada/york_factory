# Usage metering for the public data API (docs/public-interface-design.md
# §6.3): the edge Worker writes one Analytics Engine point per request, and
# Usage::Rollup re-aggregates them into usage_hourly (7 days) and usage_daily
# (kept; the billing source).
module Usage
  def self.table_name_prefix = "usage_"

  # How long hourly rows are kept.
  HOURLY_RETENTION = 7.days
end
