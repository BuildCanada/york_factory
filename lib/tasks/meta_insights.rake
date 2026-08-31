# Maintenance for Meta account insights.
#
# Instagram total_value metrics used to be fetched with no time range, so Meta
# returned a trailing-24h aggregate with no end_time and the row was stamped with
# the sync clock. Those rows cannot be attributed to a calendar day, and because
# the uniqueness index includes observed_at, each sync inserted another one rather
# than updating. They must be cleared before (or after) backfilling real days, or
# the two sets sum together.
#
# Inspect first, then purge, then backfill:
#   bin/rails 'meta_insights:undated[instagram,build_canada]'
#   bin/rails 'meta_insights:purge_undated[instagram,build_canada]'
#   bin/rails 'meta_insights:backfill[instagram,build_canada,2026-08-01,2026-08-30]'
namespace :meta_insights do
  # A correctly dated row sits exactly on a day boundary in the account's timezone.
  # Anything else was stamped with the sync clock.
  def undated_scope(platform, account_key)
    account = Metrics::MetaAccount.find_by!(platform: platform, account_key: account_key)
    zone = ActiveSupport::TimeZone[Metrics::MetaAnalyticsSync::DEFAULT_INSIGHTS_TIME_ZONE]
    metrics = Metrics::MetaAnalyticsSync::INSTAGRAM_ACCOUNT_TOTAL_METRICS +
      Metrics::MetaAnalyticsSync::INSTAGRAM_ACCOUNT_BREAKDOWNS.keys
    scope = account.insights.where(metric_name: metrics)
    ids = scope.select(:id, :observed_at).reject do |insight|
      local = insight.observed_at.in_time_zone(zone)
      local == local.beginning_of_day
    end.map(&:id)
    [ account, scope.where(id: ids) ]
  end

  desc "List Meta account insight rows stamped with the sync clock rather than a day"
  task :undated, [ :platform, :account_key ] => :environment do |_t, args|
    _account, scope = undated_scope(args.fetch(:platform), args.fetch(:account_key))
    puts "#{scope.count} undated rows"
    scope.order(:observed_at).each do |insight|
      puts "  #{insight.observed_at.iso8601}  #{insight.metric_name.ljust(22)} #{insight.value_numeric}"
    end
  end

  desc "Delete Meta account insight rows stamped with the sync clock"
  task :purge_undated, [ :platform, :account_key ] => :environment do |_t, args|
    _account, scope = undated_scope(args.fetch(:platform), args.fetch(:account_key))
    count = scope.count
    scope.delete_all
    puts "deleted #{count} undated rows"
  end

  desc "Backfill Meta account insights for a date range"
  task :backfill, [ :platform, :account_key, :from, :to ] => :environment do |_t, args|
    days = Metrics::BackfillMetaAccountInsightsJob.perform_now(
      platform: args.fetch(:platform),
      account_key: args.fetch(:account_key),
      from: args.fetch(:from),
      to: args.fetch(:to)
    )
    puts "requested #{days} days"
  end
end
