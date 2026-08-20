require "digest"

class Metrics::SocialAnalyticsRefresh
  # Chunk the upserts so one run does not build a single multi-hundred-thousand
  # row INSERT statement.
  UPSERT_BATCH_SIZE = 1_000
  IDENTITY_COLUMNS = %i[id].freeze
  BOOKKEEPING_COLUMNS = %i[created_at updated_at refreshed_at].freeze

  AD_METRICS = %w[
    spend impressions reach clicks engagements conversions conversion_value
    ctr cpc cpm cost_per_conversion roas
  ].freeze
  POST_METRICS = %w[
    impressions reach likes comments shares saves clicks views follows
    reels_average_watch_time reels_total_watch_time video_duration_seconds engagement_rate
  ].freeze
  SUBSTACK_POST_METRICS = %w[
    views cumulative_views opens opened open_rate clicks clicked click_through_rate
    delivered sent shares signups cumulative_signups subscribes cumulative_subscribes
    free_trials estimated_value engagement_rate downloads video_views video_minutes_watched
  ].freeze
  SOURCE_PRIORITY = {
    "zernio" => 1,
    "manual_export" => 2,
    "substack_api" => 3,
    "meta_api" => 3,
    "x_export" => 3
  }.freeze

  MANUAL_SOURCES = [
    [ Metrics::TwitterStat, "twitter", "x_export", true, {
      "impressions" => "content_views", "likes" => "likes",
      "engagements" => "engagements", "bookmarks" => "saves",
      "shares" => "shares", "new_follows" => "followers_gained",
      "unfollows" => "followers_lost", "replies" => "comments",
      "reposts" => "reposts", "profile_visits" => "profile_views",
      "create_post" => "posts_published", "video_views" => "video_views",
      "media_views" => "media_views"
    } ],
    [ Metrics::LinkedinStat, "linkedin", "manual_export", false, {
      "impressions_organic" => "content_views",
      "unique_impressions_organic" => "unique_reach",
      "clicks_organic" => "clicks", "reactions_organic" => "likes",
      "comments_organic" => "comments", "reposts_organic" => "shares",
      "engagement_rate_organic" => "engagement_rate"
    } ],
    [ Metrics::TiktokStat, "tiktok", "manual_export", false, {
      "video_views" => "content_views", "profile_views" => "profile_views",
      "likes" => "likes", "comments" => "comments", "shares" => "shares"
    } ],
    [ Metrics::InstagramStat, "instagram", "manual_export", false, {
      "views" => "content_views", "interactions" => "engagements",
      "new_followers" => "followers_gained"
    } ],
    [ Metrics::SubstackStat, "substack", "manual_export", true, {
      "views" => "content_views"
    } ]
  ].freeze

  META_ACCOUNT_METRICS = {
    "views" => "content_views",
    "reach" => "unique_reach",
    "accounts_engaged" => "accounts_engaged",
    "total_interactions" => "engagements",
    "follows_and_unfollows" => "net_follows",
    "profile_links_taps" => "clicks",
    "page_post_engagements" => "engagements",
    "page_daily_follows" => "followers_gained",
    "page_daily_unfollows" => "followers_lost",
    "page_views_total" => "profile_views",
    "page_media_view" => "content_views",
    "page_video_views" => "video_views"
  }.freeze
  META_CONTENT_METRICS = {
    "views" => "content_views", "reach" => "content_reach",
    "likes" => "likes", "comments" => "comments", "saved" => "saves",
    "shares" => "shares", "total_interactions" => "engagements",
    "post_clicks" => "clicks", "post_media_view" => "content_views",
    "post_video_views" => "video_views"
  }.freeze

  def initialize(now: Time.current)
    # Rounded to Postgres timestamp(6) precision so a row written with
    # refreshed_at = @now compares equal to @now afterwards; without this,
    # deactivate_stale! would see every row as untouched and deactivate it.
    @now = now.round(6)
    @entities = {}
    @observations = {}
  end

  def call
    extract_manual_sources
    extract_zernio
    extract_meta
    extract_substack
    extract_ads
    mark_current_values
    persist!

    { entities: @entities.length, observations: @observations.length }
  end

  private

  def extract_manual_sources
    MANUAL_SOURCES.each do |model, platform, source, reporting, mappings|
      model.find_each do |record|
        next if model == Metrics::InstagramStat && !record.filled?

        entity_id = account_entity(platform, record.account, source:, record:)
        period_start = record.date.in_time_zone.beginning_of_day
        period_end = model == Metrics::InstagramStat ? period_start + 1.week : period_start + 1.day
        grain = model == Metrics::InstagramStat ? "account_week" : "account_day"

        mappings.each do |source_metric, metric|
          add_observation(
            entity_id:, record:, platform:, account_key: record.account,
            source:, grain:, metric_name: metric, source_metric_name: source_metric,
            value: record.public_send(source_metric), period_start:, period_end:,
            observed_at: period_end, reporting_source: reporting,
            fallback_metric: metric == "unique_reach" && source_metric != "unique_impressions_organic",
            unit: rate_metric?(source_metric) ? "ratio" : "count"
          )
        end
      end
    end
  end

  def extract_zernio
    Metrics::SocialMediaAccount.find_each do |account|
      account_id = account_entity(
        account.platform, account.account_key, source: "zernio", record: account,
        username: account.username, name: account.display_name || account.profile_name,
        url: account.profile_url, external_id: account.zernio_account_id
      )
      reporting = %w[linkedin tiktok].include?(account.platform)

      account.metric_snapshots.find_each do |snapshot|
        add_observation(
          entity_id: account_id, record: snapshot, platform: account.platform,
          account_key: account.account_key, source: "zernio", grain: "account_snapshot",
          metric_name: "followers", source_metric_name: "followers_count",
          value: snapshot.followers_count, period_start: snapshot.observed_at,
          period_end: snapshot.observed_at, observed_at: snapshot.observed_at,
          reporting_source: true, cumulative: true
        )
      end

      account.posts.find_each do |post|
        content_id = content_entity(
          platform: account.platform, account_key: account.account_key, source: "zernio",
          record: post, external_id: post.platform_post_id.presence || post.zernio_post_id,
          name: post.content&.truncate(255), url: post.platform_post_url,
          media_type: post.media_type, published_at: post.published_at
        )
        post.metric_snapshots.find_each do |snapshot|
          POST_METRICS.each do |source_metric|
            add_observation(
              entity_id: content_id, record: snapshot, platform: account.platform,
              account_key: account.account_key, source: "zernio", grain: "content_snapshot",
              metric_name: zernio_metric_name(account.platform, source_metric),
              source_metric_name: source_metric, value: snapshot.public_send(source_metric),
              period_start: post.published_at || snapshot.observed_at,
              period_end: snapshot.observed_at, observed_at: snapshot.observed_at,
              reporting_source: reporting, cumulative: true,
              unit: metric_unit(source_metric)
            )
          end
        end
      end
    end
  end

  def extract_meta
    Metrics::MetaAccount.find_each do |account|
      account_id = account_entity(
        account.platform, account.account_key, source: "meta_api", record: account,
        username: account.username, name: account.display_name,
        external_id: account.platform_account_id
      )
      account.insights.find_each do |insight|
        metric_name = META_ACCOUNT_METRICS[insight.metric_name]
        next unless metric_name

        add_observation(
          entity_id: account_id, record: insight, platform: account.platform,
          account_key: account.account_key, source: "meta_api", grain: "account_day",
          metric_name:, source_metric_name: insight.metric_name,
          value: insight.value_numeric, period_start: insight.observed_at - 1.day,
          period_end: insight.observed_at, observed_at: insight.observed_at,
          reporting_source: account.platform == "instagram",
          fallback_metric: false
        )
      end

      account.media.find_each do |medium|
        content_id = content_entity(
          platform: account.platform, account_key: account.account_key, source: "meta_api",
          record: medium, external_id: medium.platform_media_id,
          name: medium.caption&.truncate(255), url: medium.permalink,
          media_type: medium.media_type, published_at: medium.published_at
        )
        medium.insights.find_each do |insight|
          metric_name = META_CONTENT_METRICS[insight.metric_name]
          next unless metric_name

          add_observation(
            entity_id: content_id, record: insight, platform: account.platform,
            account_key: account.account_key, source: "meta_api", grain: "content_snapshot",
            metric_name:, source_metric_name: insight.metric_name,
            value: insight.value_numeric, period_start: medium.published_at || insight.observed_at,
            period_end: insight.observed_at, observed_at: insight.observed_at,
            reporting_source: false, cumulative: true
          )
        end
      end
    end
  end

  def extract_substack
    Metrics::SubstackPublication.find_each do |publication|
      account_entity(
        "substack", publication.account_key, source: "substack_api", record: publication,
        name: publication.name, url: publication.url,
        external_id: publication.publication_id || publication.account_key
      )

      publication.posts.find_each do |post|
        content_id = content_entity(
          platform: "substack", account_key: publication.account_key,
          source: "substack_api", record: post, external_id: post.substack_post_id,
          name: post.title, url: post.canonical_url, media_type: post.post_type,
          published_at: post.published_at
        )
        post.metric_snapshots.find_each do |snapshot|
          SUBSTACK_POST_METRICS.each do |source_metric|
            add_observation(
              entity_id: content_id, record: snapshot, platform: "substack",
              account_key: publication.account_key, source: "substack_api",
              grain: "content_snapshot", metric_name: substack_metric_name(source_metric),
              source_metric_name: source_metric, value: snapshot.public_send(source_metric),
              period_start: post.published_at || snapshot.observed_at,
              period_end: snapshot.observed_at, observed_at: snapshot.observed_at,
              reporting_source: false, cumulative: source_metric.start_with?("cumulative_"),
              unit: metric_unit(source_metric)
            )
          end
        end
      end
    end
  end

  def extract_ads
    Metrics::SocialMediaAdAccount.find_each do |ad_account|
      account = ad_account.account
      account_entity(
        ad_account.platform, account.account_key, source: "zernio", record: account,
        username: account.username, name: account.display_name || account.profile_name,
        url: account.profile_url, external_id: account.zernio_account_id
      )
      entity_id = ad_entity(
        entity_type: "ad_account", platform: ad_account.platform,
        account_key: account.account_key, source: "zernio", record: ad_account,
        external_id: ad_account.platform_ad_account_id, name: ad_account.name
      )
      extract_ad_metrics(ad_account.daily_metrics, entity_id, ad_account.platform,
        account.account_key, "ad_account")
    end

    Metrics::SocialMediaAdCampaign.find_each do |campaign|
      entity_id = ad_entity(
        entity_type: "campaign", platform: campaign.platform,
        account_key: campaign.account.account_key, source: "zernio", record: campaign,
        external_id: campaign.platform_campaign_id, name: campaign.name,
        parent_id: campaign.ad_account && ad_entity_id("ad_account", campaign.platform,
          campaign.account.account_key, campaign.ad_account.platform_ad_account_id)
      )
      extract_ad_metrics(campaign.daily_metrics, entity_id, campaign.platform,
        campaign.account.account_key, "campaign")
    end

    Metrics::SocialMediaAd.find_each do |ad|
      entity_id = ad_entity(
        entity_type: "ad", platform: ad.platform, account_key: ad.account.account_key,
        source: "zernio", record: ad, external_id: ad.platform_ad_id.presence || ad.zernio_ad_id,
        name: ad.name, parent_id: ad.campaign && ad_entity_id("campaign", ad.platform,
          ad.account.account_key, ad.campaign.platform_campaign_id)
      )
      extract_ad_metrics(ad.daily_metrics, entity_id, ad.platform, ad.account.account_key, "ad")
    end
  end

  def extract_ad_metrics(scope, entity_id, platform, account_key, entity_type)
    scope.find_each do |metric|
      period_start = metric.date.in_time_zone.beginning_of_day
      AD_METRICS.each do |source_metric|
        add_observation(
          entity_id:, record: metric, platform:, account_key:, source: "zernio",
          grain: "entity_day", metric_name: source_metric,
          source_metric_name: source_metric, value: metric.public_send(source_metric),
          period_start:, period_end: period_start + 1.day, observed_at: period_start + 1.day,
          reporting_source: entity_type == "ad_account", paid: true,
          unit: metric_unit(source_metric)
        )
      end
    end
  end

  def account_entity(platform, account_key, source:, record:, **attributes)
    id = account_entity_id(platform, account_key)
    add_entity(id:, entity_type: "account", platform:, account_key:, source:, record:,
      external_id: attributes[:external_id] || account_key, **attributes.except(:external_id))
    id
  end

  def content_entity(platform:, account_key:, source:, record:, external_id:, **attributes)
    id = "content:#{platform}:#{external_id}"
    add_entity(id:, parent_id: account_entity_id(platform, account_key),
      entity_type: "content", platform:, account_key:, external_id:, source:, record:, **attributes)
    id
  end

  def ad_entity(entity_type:, platform:, account_key:, source:, record:, external_id:, **attributes)
    id = ad_entity_id(entity_type, platform, account_key, external_id)
    parent_id = attributes.delete(:parent_id) || account_entity_id(platform, account_key)
    add_entity(id:, parent_id:, entity_type:, platform:, account_key:, external_id:,
      source:, record:, **attributes)
    id
  end

  def add_entity(id:, entity_type:, platform:, account_key:, source:, record:, **attributes)
    existing = @entities[id]
    return existing if existing && SOURCE_PRIORITY.fetch(existing[:source], 0) > SOURCE_PRIORITY.fetch(source, 0)

    @entities[id] = {
      id:, parent_id: attributes[:parent_id], entity_type:, platform:, account_key:,
      external_id: attributes[:external_id], name: attributes[:name],
      username: attributes[:username], url: attributes[:url], media_type: attributes[:media_type],
      published_at: attributes[:published_at], source:,
      source_record_type: record.class.base_class.name, source_record_id: record.id.to_s,
      active: true, source_updated_at: record.updated_at, refreshed_at: @now,
      created_at: @now, updated_at: @now
    }
  end

  def add_observation(entity_id:, record:, platform:, account_key:, source:, grain:,
    metric_name:, source_metric_name:, value:, period_start:, period_end:, observed_at:,
    reporting_source:, cumulative: false, paid: false, fallback_metric: false, unit: "count")
    return if value.nil?

    id = Digest::SHA256.hexdigest([
      record.class.base_class.name, record.id, entity_id, source_metric_name, metric_name
    ].join(":"))
    @observations[id] = {
      id:, social_entity_id: entity_id, entity_type: @entities.fetch(entity_id)[:entity_type],
      platform:, account_key:, source:,
      source_record_type: record.class.base_class.name, source_record_id: record.id.to_s,
      grain:, metric_name:, source_metric_name:, value:, unit:,
      period_start:, period_end:, observed_at:, cumulative:, paid:,
      reporting_source:, fallback_metric:, current_value: true, active: true,
      source_updated_at: record.updated_at, refreshed_at: @now,
      created_at: @now, updated_at: @now
    }
  end

  def mark_current_values
    grouped = @observations.values.select { |row| row[:cumulative] }.group_by do |row|
      [ row[:social_entity_id], row[:source], row[:metric_name] ]
    end
    grouped.each_value do |rows|
      latest = rows.max_by { |row| [ row[:observed_at], row[:source_updated_at] ] }
      rows.each { |row| row[:current_value] = row.equal?(latest) }
    end
  end

  # PostHog syncs both tables incrementally with `updated_at` as the cursor
  # (see docs/metrics/social_analytics.md), so `updated_at` must move only when
  # a row's values actually change. `refreshed_at` carries "seen in this run"
  # instead, which is also what lets us deactivate the rows we no longer produce
  # without enumerating every id.
  def persist!
    Metrics::SocialEntity.transaction do
      upsert_rows!(Metrics::SocialEntity, @entities.values)
      upsert_rows!(Metrics::SocialMetricObservation, @observations.values)
      deactivate_stale!(Metrics::SocialEntity)
      deactivate_stale!(Metrics::SocialMetricObservation)
    end
  end

  def upsert_rows!(model, rows)
    return if rows.empty?

    compared = rows.first.keys - IDENTITY_COLUMNS - BOOKKEEPING_COLUMNS
    clause = Arel.sql(on_duplicate_clause(model, compared))
    rows.each_slice(UPSERT_BATCH_SIZE) do |slice|
      model.upsert_all(slice, unique_by: :id, on_duplicate: clause)
    end
  end

  # Assigns every real column, always advances refreshed_at, and advances
  # updated_at only when at least one compared column differs. created_at is
  # left out entirely so the row keeps its original insert time.
  def on_duplicate_clause(model, compared)
    connection = model.connection
    table = model.quoted_table_name
    quoted = compared.map { |column| connection.quote_column_name(column) }

    assignments = quoted.map { |column| "#{column} = excluded.#{column}" }
    assignments << "#{connection.quote_column_name('refreshed_at')} = excluded.#{connection.quote_column_name('refreshed_at')}"
    assignments << <<~SQL.squish
      #{connection.quote_column_name('updated_at')} = CASE
        WHEN ROW(#{quoted.map { |column| "#{table}.#{column}" }.join(', ')})
             IS DISTINCT FROM ROW(#{quoted.map { |column| "excluded.#{column}" }.join(', ')})
        THEN excluded.#{connection.quote_column_name('updated_at')}
        ELSE #{table}.#{connection.quote_column_name('updated_at')}
      END
    SQL

    assignments.join(", ")
  end

  # Anything still active that this run did not touch is no longer produced
  # upstream. Only these rows genuinely changed, so only these bump updated_at.
  def deactivate_stale!(model)
    model.where(active: true)
      .where(model.arel_table[:refreshed_at].lt(@now))
      .update_all(active: false, updated_at: @now)
  end

  def account_entity_id(platform, account_key)
    "account:#{platform}:#{account_key}"
  end

  def ad_entity_id(entity_type, platform, account_key, external_id)
    "#{entity_type}:#{platform}:#{account_key}:#{external_id}"
  end

  def zernio_metric_name(platform, source_metric)
    return "content_views" if source_metric == "impressions" && %w[twitter linkedin facebook].include?(platform)
    return "content_views" if source_metric == "views" && %w[tiktok instagram].include?(platform)
    return "content_reach" if source_metric == "reach"

    source_metric
  end

  def substack_metric_name(source_metric)
    return "content_views" if source_metric == "views"

    source_metric
  end

  def rate_metric?(metric)
    metric.include?("rate") || %w[ctr cpc cpm roas cost_per_conversion].include?(metric)
  end

  def metric_unit(metric)
    return "currency" if %w[spend conversion_value cpc cpm cost_per_conversion estimated_value].include?(metric)
    return "ratio" if rate_metric?(metric)
    return "seconds" if metric == "video_duration_seconds"
    return "milliseconds" if metric.include?("watch_time")

    "count"
  end
end
