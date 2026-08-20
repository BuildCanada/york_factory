require "test_helper"

class Metrics::SocialAnalyticsRefreshTest < ActiveSupport::TestCase
  setup do
    Metrics::SocialMetricObservation.delete_all
    Metrics::SocialEntity.delete_all
    @now = Time.zone.parse("2026-08-13 06:00:00")
  end

  test "normalizes account metrics and separates reporting sources from cross-checks" do
    Metrics::TwitterStat.create!(
      account: "build_canada", date: Date.new(2026, 8, 12),
      impressions: 100, likes: 5
    )
    Metrics::LinkedinStat.create!(
      account: "build_canada", date: Date.new(2026, 8, 12),
      impressions_organic: 50, unique_impressions_organic: 40
    )

    result = Metrics::SocialAnalyticsRefresh.new(now: @now).call

    assert_operator result[:entities], :>=, 2
    twitter_views = Metrics::SocialMetricObservation.find_by!(
      platform: "twitter", account_key: "build_canada",
      metric_name: "content_views", source_metric_name: "impressions"
    )
    assert_equal 100, twitter_views.value
    assert twitter_views.reporting_source?
    assert_equal "account_day", twitter_views.grain

    linkedin_reach = Metrics::SocialMetricObservation.find_by!(
      platform: "linkedin", account_key: "build_canada",
      metric_name: "unique_reach"
    )
    assert_equal 40, linkedin_reach.value
    refute linkedin_reach.reporting_source?
    refute linkedin_reach.fallback_metric?
  end

  test "keeps per-content reach distinct from account-level unique reach" do
    account = Metrics::MetaAccount.create!(
      platform: "instagram", account_key: "build_toronto",
      platform_account_id: "ig-account", username: "build_toronto"
    )
    account.insights.create!(
      metric_name: "reach", period: "day", observed_at: @now,
      value_numeric: 1_000
    )
    medium = account.media.create!(
      platform_media_id: "ig-post", published_at: @now - 2.days
    )
    earlier_insight = medium.insights.create!(
      metric_name: "reach", period: "lifetime", observed_at: @now - 1.hour,
      value_numeric: 500
    )
    medium.insights.create!(
      metric_name: "reach", period: "lifetime", observed_at: @now,
      value_numeric: 600
    )

    Metrics::SocialAnalyticsRefresh.new(now: @now).call

    account_reach = Metrics::SocialMetricObservation.find_by!(
      social_entity_id: "account:instagram:build_toronto", metric_name: "unique_reach"
    )
    content_reach = Metrics::SocialMetricObservation.find_by!(
      social_entity_id: "content:instagram:ig-post", metric_name: "content_reach",
      current_value: true
    )
    assert_equal 1_000, account_reach.value
    assert account_reach.reporting_source?
    assert_equal 600, content_reach.value
    refute content_reach.reporting_source?
    assert content_reach.current_value?
    refute Metrics::SocialMetricObservation.find_by!(
      source_record_type: "Metrics::MetaMediaInsight",
      source_record_id: earlier_insight.id.to_s
    ).current_value?
    refute Metrics::SocialMetricObservation.exists?(
      social_entity_id: "content:instagram:ig-post", metric_name: "unique_reach"
    )
  end

  test "reports current follower totals for every social platform" do
    platforms = %w[twitter instagram linkedin tiktok facebook threads bluesky]
    platforms.each_with_index do |platform, index|
      account = Metrics::SocialMediaAccount.create!(
        zernio_account_id: "zernio-#{platform}",
        zernio_profile_id: "profile-#{platform}",
        profile_name: "Build Canada #{platform}",
        platform:, account_key: "followers_#{platform}", username: "buildcanada#{index}"
      )
      account.metric_snapshots.create!(
        observed_at: @now, scraped_at: @now, followers_count: 1_000 + index
      )
    end

    Metrics::SocialAnalyticsRefresh.new(now: @now).call

    followers = Metrics::SocialMetricObservation.reportable.where(
      metric_name: "followers", platform: platforms
    )
    assert_equal platforms.sort, followers.distinct.order(:platform).pluck(:platform)
    assert_equal platforms.length, followers.count
    assert followers.all?(&:cumulative?)
  end

  test "is idempotent and deactivates observations removed from source tables" do
    stat = Metrics::TwitterStat.create!(
      account: "build_canada", date: Date.new(2026, 8, 12), impressions: 100
    )
    refresh = Metrics::SocialAnalyticsRefresh.new(now: @now)
    refresh.call
    ids = Metrics::SocialMetricObservation.where(
      source_record_type: "Metrics::TwitterStat", source_record_id: stat.id.to_s
    ).order(:id).pluck(:id)

    Metrics::SocialAnalyticsRefresh.new(now: @now + 6.hours).call
    assert_equal ids, Metrics::SocialMetricObservation.order(:id).pluck(:id)

    stat.delete
    Metrics::SocialAnalyticsRefresh.new(now: @now + 12.hours).call
    refute Metrics::SocialMetricObservation.find(ids.first).active?
  end

  test "leaves updated_at alone when a rerun changes nothing" do
    Metrics::TwitterStat.create!(
      account: "build_canada", date: Date.new(2026, 8, 12), impressions: 100
    )
    Metrics::SocialAnalyticsRefresh.new(now: @now).call
    before = Metrics::SocialMetricObservation.order(:id).pluck(:id, :updated_at, :created_at)

    later = @now + 6.hours
    Metrics::SocialAnalyticsRefresh.new(now: later).call

    assert_equal before, Metrics::SocialMetricObservation.order(:id).pluck(:id, :updated_at, :created_at)
    assert Metrics::SocialMetricObservation.all.all?(&:active?)
    # refreshed_at still records that the run saw every row.
    assert_equal [ later ], Metrics::SocialMetricObservation.distinct.pluck(:refreshed_at)
    assert_equal [ later ], Metrics::SocialEntity.distinct.pluck(:refreshed_at)
  end

  test "advances updated_at only for rows whose values changed" do
    changing = Metrics::TwitterStat.create!(
      account: "build_canada", date: Date.new(2026, 8, 12), impressions: 100
    )
    Metrics::TwitterStat.create!(
      account: "canada_spends", date: Date.new(2026, 8, 12), impressions: 7
    )
    Metrics::SocialAnalyticsRefresh.new(now: @now).call

    untouched = Metrics::SocialMetricObservation.find_by!(
      platform: "twitter", account_key: "canada_spends", source_metric_name: "impressions"
    )
    changing.update!(impressions: 250)

    later = @now + 6.hours
    Metrics::SocialAnalyticsRefresh.new(now: later).call

    changed = Metrics::SocialMetricObservation.find_by!(
      platform: "twitter", account_key: "build_canada", source_metric_name: "impressions"
    )
    assert_equal 250, changed.value
    assert_equal later, changed.updated_at
    assert_equal @now, untouched.reload.updated_at
  end

  test "deactivating a stale row advances its updated_at" do
    stat = Metrics::TwitterStat.create!(
      account: "build_canada", date: Date.new(2026, 8, 12), impressions: 100
    )
    Metrics::SocialAnalyticsRefresh.new(now: @now).call
    observation = Metrics::SocialMetricObservation.find_by!(
      source_record_type: "Metrics::TwitterStat", source_record_id: stat.id.to_s,
      source_metric_name: "impressions"
    )

    stat.delete
    later = @now + 6.hours
    Metrics::SocialAnalyticsRefresh.new(now: later).call

    observation.reload
    refute observation.active?
    assert_equal later, observation.updated_at
  end
end
