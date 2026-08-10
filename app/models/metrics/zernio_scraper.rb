module Metrics
  class ZernioScraper
    PAGE_SIZE = 100
    HISTORY_DAYS = 365
    AD_HISTORY_DAYS = 730

    SOCIAL_POST_TYPES = {
      "twitter" => [ "SocialPost::X" ],
      "instagram" => [ "SocialPost::Instagram", "SocialPost::InstagramReel" ],
      "tiktok" => [ "SocialPost::TikTok" ]
    }.freeze

    METRIC_FIELDS = {
      impressions: "impressions",
      reach: "reach",
      likes: "likes",
      comments: "comments",
      shares: "shares",
      saves: "saves",
      clicks: "clicks",
      views: "views",
      follows: "follows",
      reels_average_watch_time: "igReelsAvgWatchTime",
      reels_total_watch_time: "igReelsVideoViewTotalTime",
      video_duration_seconds: "videoDurationSeconds",
      engagement_rate: "engagementRate"
    }.freeze

    AD_METRIC_FIELDS = {
      spend: %w[spend],
      impressions: %w[impressions],
      reach: %w[reach],
      clicks: %w[clicks],
      engagements: %w[engagements engagement],
      conversions: %w[conversions],
      conversion_value: %w[conversionValue purchaseValue],
      ctr: %w[ctr clickThroughRate],
      cpc: %w[cpc costPerClick],
      cpm: %w[cpm costPerMille],
      cost_per_conversion: %w[costPerConversion],
      roas: %w[roas]
    }.freeze

    def initialize(client:, now: Time.current)
      @client = client
      @scraped_at = now
    end

    def sync_accounts!
      response = @client.get("/accounts")
      response.fetch("accounts").each { |payload| sync_account!(payload) }
    end

    def sync_page!(page:)
      response = @client.get("/analytics", params: analytics_params(page))
      response.fetch("posts").each { |payload| sync_post!(payload) }

      pagination = response.fetch("pagination")
      current_page = pagination.fetch("page")
      {
        processed: response.fetch("posts").size,
        total: pagination.fetch("total"),
        next_page: current_page < pagination.fetch("pages") ? current_page + 1 : nil
      }
    end

    def sync_ad_account!(account_id:)
      account = Metrics::SocialMediaAccount.find(account_id)
      response = @client.get("/ads/accounts", params: { accountId: account.zernio_account_id })
      payloads_from(response, "accounts", "adAccounts").each do |payload|
        sync_ad_account_payload!(account, payload)
      end
    rescue Metrics::ZernioClient::Error => e
      Rails.logger.warn("[Zernio] skipped ad accounts for #{account&.zernio_account_id}: #{e.message}")
      0
    end

    def sync_ad_campaigns_page!(page:)
      response = @client.get("/ads/campaigns", params: ad_list_params(page))
      payloads = payloads_from(response, "campaigns")
      payloads.each { |payload| sync_ad_campaign!(payload) }
      pagination_result(response, payloads.size)
    end

    def sync_ads_page!(page:)
      response = @client.get("/ads", params: ad_list_params(page))
      payloads = payloads_from(response, "ads")
      payloads.each { |payload| sync_ad!(payload) }
      pagination_result(response, payloads.size)
    end

    def sync_ad_account_analytics!(id:)
      ad_account = Metrics::SocialMediaAdAccount.find(id)
      response = @client.get("/ads/timeline", params: ad_analytics_params.merge(
        accountId: ad_account.account.zernio_account_id,
        adAccountId: ad_account.platform_ad_account_id
      ))
      sync_daily_metrics!(ad_account.daily_metrics, daily_rows(response))
      assign_and_save_if_changed!(ad_account,
        analytics_payload: response.except("rows", "daily"),
        backfill_pending: response.fetch("backfillPending", false))
    rescue Metrics::ZernioClient::Error => e
      Rails.logger.warn("[Zernio] skipped analytics for ad account #{id}: #{e.message}")
    end

    def sync_ad_campaign_analytics!(id:)
      campaign = Metrics::SocialMediaAdCampaign.find(id)
      response = @client.get("/ads/campaigns/#{campaign.platform_campaign_id}/analytics",
        params: ad_analytics_params)
      analytics = response["analytics"] || response
      sync_daily_metrics!(campaign.daily_metrics, daily_rows(analytics))
      assign_and_save_if_changed!(campaign,
        metrics_payload: analytics["summary"] || campaign.metrics_payload,
        backfill_pending: response.fetch("backfillPending", analytics.fetch("backfillPending", false)))
    rescue Metrics::ZernioClient::Error => e
      Rails.logger.warn("[Zernio] skipped analytics for campaign #{id}: #{e.message}")
    end

    def sync_ad_analytics!(id:)
      ad = Metrics::SocialMediaAd.find(id)
      response = @client.get("/ads/#{ad.zernio_ad_id}/analytics", params: ad_analytics_params)
      analytics = response["analytics"] || response
      sync_daily_metrics!(ad.daily_metrics, daily_rows(analytics))
      assign_and_save_if_changed!(ad,
        metrics_payload: analytics["summary"] || ad.metrics_payload,
        last_synced_at: parse_time(analytics.dig("summary", "lastSyncedAt")) || ad.last_synced_at,
        backfill_pending: response.fetch("backfillPending", analytics.fetch("backfillPending", false)))
    rescue Metrics::ZernioClient::Error => e
      Rails.logger.warn("[Zernio] skipped analytics for ad #{id}: #{e.message}")
    end

    private

    def analytics_params(page)
      {
        source: "all",
        fromDate: (@scraped_at.to_date - HISTORY_DAYS).iso8601,
        toDate: @scraped_at.to_date.iso8601,
        limit: PAGE_SIZE,
        page: page,
        sortBy: "date",
        order: "asc"
      }
    end

    def ad_list_params(page)
      ad_analytics_params.merge(source: "all", limit: PAGE_SIZE, page: page)
    end

    def ad_analytics_params
      {
        fromDate: (@scraped_at.to_date - AD_HISTORY_DAYS).iso8601,
        toDate: @scraped_at.to_date.iso8601
      }
    end

    def sync_account!(payload)
      profile = payload.fetch("profileId")
      profile_id = profile.is_a?(Hash) ? profile.fetch("_id") : profile
      profile_name = profile.is_a?(Hash) ? profile.fetch("name") : payload["displayName"]
      account = Metrics::SocialMediaAccount.find_or_initialize_by(
        zernio_account_id: payload.fetch("_id")
      )
      account.assign_attributes(
        zernio_profile_id: profile_id,
        profile_name: profile_name,
        platform: payload.fetch("platform"),
        account_key: profile_name.parameterize(separator: "_"),
        username: payload.fetch("username"),
        display_name: payload["displayName"],
        profile_url: payload["profileUrl"],
        enabled: payload.fetch("enabled", true),
        ads_status: payload["adsStatus"],
        source_updated_at: parse_time(payload["updatedAt"])
      )
      account.save!

      sync_account_snapshot!(account, payload)
      account.link_existing_metrics!
    end

    def sync_account_snapshot!(account, payload)
      return if payload["followersCount"].nil?

      observed_at = parse_time(payload["followersLastUpdated"]) || @scraped_at
      snapshot = account.metric_snapshots.find_or_initialize_by(observed_at: observed_at)
      snapshot.assign_attributes(followers_count: payload["followersCount"])
      save_changed_snapshot!(snapshot)
    end

    def sync_post!(payload)
      platform_entries(payload).each do |platform_payload|
        account = Metrics::SocialMediaAccount.find_by!(
          zernio_account_id: platform_payload.fetch("accountId")
        )
        post = account.posts.find_or_initialize_by(zernio_post_id: payload.fetch("_id"))
        post.assign_attributes(post_attributes(payload, platform_payload))
        post.social_post ||= matching_social_post(post)
        post.save!
        sync_post_snapshot!(post, platform_payload["analytics"] || payload["analytics"] || {})
      end
    end

    def platform_entries(payload)
      entries = Array(payload["platforms"])
      return entries if entries.any?

      [ {
        "platform" => payload.fetch("platform"),
        "accountId" => payload.fetch("accountId"),
        "accountUsername" => payload["accountUsername"],
        "platformPostId" => payload["platformPostId"],
        "platformPostUrl" => payload["platformPostUrl"],
        "status" => payload.fetch("status"),
        "analytics" => payload["analytics"]
      } ]
    end

    def post_attributes(payload, platform_payload)
      {
        late_post_id: payload["latePostId"],
        platform_post_id: platform_payload["platformPostId"],
        platform: platform_payload.fetch("platform"),
        account_username: platform_payload["accountUsername"],
        status: platform_payload["status"] || payload.fetch("status"),
        content: payload["content"],
        platform_post_url: platform_payload["platformPostUrl"] || payload["platformPostUrl"],
        thumbnail_url: payload["thumbnailUrl"],
        media_type: payload["mediaType"],
        published_at: parse_time(payload["publishedAt"]),
        scheduled_for: parse_time(payload["scheduledFor"]),
        external: payload.fetch("isExternal", false),
        ad: payload.fetch("isAd", false),
        source_payload: payload.slice("profileId", "mediaItems")
      }
    end

    def sync_post_snapshot!(post, analytics)
      observed_at = parse_time(analytics["lastUpdated"]) || @scraped_at
      snapshot = post.metric_snapshots.find_or_initialize_by(observed_at: observed_at)
      attributes = METRIC_FIELDS.to_h do |column, source_key|
        value = analytics[source_key]
        value = 0 if value.nil? && !column.in?(%i[video_duration_seconds engagement_rate])
        [ column, value ]
      end
      snapshot.assign_attributes(attributes.merge(source_payload: analytics))
      save_changed_snapshot!(snapshot)
    end

    def sync_ad_account_payload!(account, payload)
      platform_ad_account_id = first_value(payload, "id", "accountId", "adAccountId", "_id")
      ad_account = account.ad_accounts.find_or_initialize_by(
        platform_ad_account_id: platform_ad_account_id
      )
      assign_and_save_if_changed!(ad_account,
        platform: payload["platform"] || normalized_ad_platform(account.platform),
        name: first_value(payload, "name", "accountName"),
        business_name: payload["businessName"],
        status: first_value(payload, "status", "accountStatus"),
        currency: payload["currency"],
        timezone_name: first_value(payload, "timezoneName", "timezone"),
        timezone_offset_hours: first_value(payload,
          "timezoneOffsetHours", "timezoneOffsetHoursUtc", "timezoneOffset"),
        minimum_daily_budget: payload["minimumDailyBudget"],
        selectable: payload["selectable"],
        unusable_reason: payload["unusableReason"],
        source_payload: payload)
      ad_account
    end

    def sync_ad_campaign!(payload)
      account = source_account!(payload)
      platform = payload.fetch("platform")
      campaign = account.ad_campaigns.find_or_initialize_by(
        platform: platform,
        platform_campaign_id: payload.fetch("platformCampaignId")
      )
      platform_ad_account_id = payload["platformAdAccountId"]
      assign_and_save_if_changed!(campaign,
        ad_account: find_ad_account(account, platform_ad_account_id),
        platform_ad_account_id: platform_ad_account_id,
        name: first_value(payload, "name", "campaignName"),
        status: payload["status"],
        currency: payload["currency"],
        channel_type: first_value(payload, "channelType", "advertisingChannelType", "type"),
        ad_count: payload["adCount"],
        external: payload.fetch("isExternal", payload.fetch("external", false)),
        platform_created_at: parse_time(payload["platformCreatedAt"] || payload["createdAt"]),
        earliest_ad_at: parse_time(payload["earliestAdAt"] || payload["earliestAd"]),
        latest_ad_at: parse_time(payload["latestAdAt"] || payload["latestAd"]),
        budget_payload: payload["budget"] || payload.slice("dailyBudget", "lifetimeBudget"),
        metrics_payload: payload["metrics"] || {},
        source_payload: payload)
    end

    def sync_ad!(payload)
      account = source_account!(payload)
      platform = payload.fetch("platform")
      platform_campaign_id = payload["platformCampaignId"]
      ad = Metrics::SocialMediaAd.find_or_initialize_by(zernio_ad_id: payload.fetch("_id"))
      assign_and_save_if_changed!(ad,
        account: account,
        ad_account: find_ad_account(account, payload["platformAdAccountId"]),
        campaign: find_campaign(account, platform, platform_campaign_id),
        platform_ad_id: payload["platformAdId"],
        platform_ad_account_id: payload["platformAdAccountId"],
        platform_campaign_id: platform_campaign_id,
        platform_ad_set_id: payload["platformAdSetId"],
        platform: platform,
        name: payload["name"],
        ad_set_name: payload["adSetName"],
        status: payload["status"],
        goal: payload["goal"],
        ad_type: first_value(payload, "adType", "type"),
        currency: payload["currency"],
        external: payload.fetch("isExternal", payload.fetch("external", false)),
        platform_created_at: parse_time(payload["platformCreatedAt"] || payload["createdAt"]),
        source_updated_at: parse_time(payload["updatedAt"]),
        last_synced_at: parse_time(payload["lastSyncedAt"] || payload.dig("metrics", "lastSyncedAt")),
        creative_payload: payload["creative"] || {},
        metrics_payload: payload["metrics"] || {},
        source_payload: payload)
    end

    def sync_daily_metrics!(association, rows)
      rows.each do |payload|
        metric = association.find_or_initialize_by(date: Date.iso8601(payload.fetch("date")))
        attributes = AD_METRIC_FIELDS.to_h do |column, keys|
          [ column, first_value(payload, *keys) ]
        end
        assign_and_save_if_changed!(metric, attributes.merge(source_payload: payload))
      end
    end

    def source_account!(payload)
      account_id = payload["accountId"]
      account_id = first_value(account_id, "_id", "id") if account_id.is_a?(Hash)
      Metrics::SocialMediaAccount.find_by!(zernio_account_id: account_id)
    end

    def find_ad_account(account, platform_ad_account_id)
      return if platform_ad_account_id.blank?

      account.ad_accounts.find_by(platform_ad_account_id: platform_ad_account_id)
    end

    def find_campaign(account, platform, platform_campaign_id)
      return if platform_campaign_id.blank?

      account.ad_campaigns.find_by(platform: platform, platform_campaign_id: platform_campaign_id)
    end

    def normalized_ad_platform(platform)
      { "googleads" => "google", "metaads" => "meta" }.fetch(platform, platform)
    end

    def daily_rows(payload)
      Array(payload["daily"] || payload["rows"])
    end

    def payloads_from(response, *keys)
      key = keys.find { |candidate| response[candidate].is_a?(Array) }
      Array(key ? response[key] : response["data"])
    end

    def pagination_result(response, processed)
      pagination = response["pagination"] || {}
      current_page = pagination["page"] || pagination["currentPage"] || 1
      total_pages = pagination["pages"] || pagination["totalPages"] || current_page
      {
        processed: processed,
        total: pagination["total"] || processed,
        next_page: current_page < total_pages ? current_page + 1 : nil
      }
    end

    def first_value(payload, *keys)
      keys.each do |key|
        value = payload[key]
        return value unless value.nil?
      end
      nil
    end

    def matching_social_post(post)
      types = SOCIAL_POST_TYPES[post.platform]
      return unless types

      SocialPost.where(type: types, external_id: post.platform_post_id).first ||
        SocialPost.where(type: types, url: post.platform_post_url).first
    end

    def parse_time(value)
      Time.zone.parse(value.to_s) if value.present?
    end

    # Keep updated_at usable as an incremental-sync cursor. A successful scrape
    # of identical source data is a no-op; scraped_at advances only when the
    # snapshot is first seen or its values actually change.
    def save_changed_snapshot!(snapshot)
      return unless snapshot.new_record? || snapshot.changed?

      snapshot.scraped_at = @scraped_at
      snapshot.save!
    end

    def assign_and_save_if_changed!(record, attributes)
      record.assign_attributes(attributes)
      record.save! if record.new_record? || record.changed?
      record
    end
  end
end
