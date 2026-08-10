module Metrics
  class ZernioScraper
    PAGE_SIZE = 100
    HISTORY_DAYS = 365

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
  end
end
