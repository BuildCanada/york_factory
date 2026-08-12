module Metrics
  class MetaAnalyticsSync
    MEDIA_LOOKBACK_DAYS = 30
    ACCOUNT_FIELDS = {
      "facebook" => %w[id name username link],
      "instagram" => %w[id name username profile_picture_url]
    }.freeze
    MEDIA_FIELDS = {
      "facebook" => %w[id message permalink_url created_time],
      "instagram" => %w[id caption media_type permalink timestamp]
    }.freeze
    MEDIA_EDGE = { "facebook" => "posts", "instagram" => "media" }.freeze
    INSTAGRAM_ACCOUNT_TOTAL_METRICS = %w[
      views accounts_engaged total_interactions profile_links_taps
    ].freeze
    INSTAGRAM_ACCOUNT_BREAKDOWNS = {
      "follows_and_unfollows" => "follow_type"
    }.freeze
    DEFAULT_ACCOUNT_METRICS = {
      "facebook" => %w[
        page_post_engagements page_daily_follows page_daily_unfollows
        page_views_total page_media_view page_video_views
      ],
      "instagram" => %w[
        views reach accounts_engaged total_interactions
        follows_and_unfollows profile_links_taps
      ]
    }.freeze
    DEFAULT_MEDIA_METRICS = {
      "facebook" => %w[
        post_clicks post_media_view post_video_views
        post_reactions_by_type_total post_activity_by_action_type
      ],
      "instagram" => %w[
        views reach likes comments saved shares total_interactions
      ]
    }.freeze

    def initialize(client:, now: Time.current)
      @client = client
      @now = now
    end

    def sync!(platform:, account_key:, platform_account_id:, account_metrics: [], media_metrics: [])
      validate_account!(platform, account_key)
      profile = @client.get(platform_account_id, params: {
        fields: ACCOUNT_FIELDS.fetch(platform).join(",")
      })
      account = upsert_account!(platform, account_key, platform_account_id, profile)
      sync_insights!(account.insights, platform_account_id, account_metrics,
        platform: platform, scope: :account)
      sync_media!(account, platform_account_id, media_metrics)
      account.update!(last_synced_at: @now)
      account
    end

    private

    def validate_account!(platform, account_key)
      allowed = Metrics::MetaAccount::ACCOUNT_KEYS[platform]
      raise ArgumentError, "Unsupported Meta platform #{platform.inspect}" unless allowed
      return if allowed.include?(account_key)

      raise ArgumentError, "Unsupported #{platform} account #{account_key.inspect}"
    end

    def upsert_account!(platform, account_key, platform_account_id, payload)
      account = Metrics::MetaAccount.find_or_initialize_by(platform: platform, account_key: account_key)
      account.assign_attributes(
        platform_account_id: platform_account_id,
        username: payload["username"],
        display_name: payload["name"],
        source_payload: payload
      )
      account.save!
      account
    end

    def sync_media!(account, platform_account_id, metric_names)
      params = {
        fields: MEDIA_FIELDS.fetch(account.platform).join(","),
        limit: 100
      }
      params[:since] = media_cutoff.iso8601 if account.platform == "facebook"

      each_page("#{platform_account_id}/#{MEDIA_EDGE.fetch(account.platform)}", params: params) do |payload|
        published_at = media_attributes(account.platform, payload)[:published_at]
        next :stop if account.platform == "instagram" && published_at && published_at < media_cutoff

        medium = account.media.find_or_initialize_by(platform_media_id: payload.fetch("id"))
        medium.assign_attributes(media_attributes(account.platform, payload))
        medium.save!
        sync_insights!(medium.insights, medium.platform_media_id, metric_names,
          platform: account.platform, scope: :media)
      end
    end

    def media_cutoff
      @now - MEDIA_LOOKBACK_DAYS.days
    end

    def media_attributes(platform, payload)
      if platform == "instagram"
        {
          media_type: payload["media_type"],
          caption: payload["caption"],
          permalink: payload["permalink"],
          published_at: parse_time(payload["timestamp"]),
          source_payload: payload
        }
      else
        {
          media_type: "post",
          caption: payload["message"],
          permalink: payload["permalink_url"],
          published_at: parse_time(payload["created_time"]),
          source_payload: payload
        }
      end
    end

    def sync_insights!(association, object_id, metric_names, platform:, scope:)
      return if metric_names.blank?

      insight_queries(platform, scope, metric_names).each do |params|
        each_page("#{object_id}/insights", params: params, follow_paging: false) do |metric|
          sync_metric!(association, metric)
        end
      end
    end

    def sync_metric!(association, metric)
        values = Array(metric["values"])
        values = [ { "value" => metric["value"] } ] if values.empty? && metric.key?("value")
        if values.empty? && metric.key?("total_value")
          total_value = metric["total_value"]
          value = total_value.is_a?(Hash) && total_value.key?("value") ? total_value["value"] : total_value
          values = [ { "value" => value } ]
        end
        values.each do |value|
          observed_at = parse_time(value["end_time"]) || @now
          insight = association.find_or_initialize_by(
            metric_name: metric.fetch("name"),
            period: metric["period"],
            observed_at: observed_at
          )
          raw_value = value["value"]
          insight.assign_attributes(
            value_numeric: numeric_value(raw_value),
            value_payload: raw_value.is_a?(Hash) || raw_value.is_a?(Array) ? raw_value : {},
            source_payload: metric.merge("value_entry" => value)
          )
          insight.save!
        end
    end

    def insight_queries(platform, scope, metric_names)
      names = metric_names.map(&:to_s)
      default_params = { period: "day" } if scope == :account
      default_params ||= {}
      return [ default_params.merge(metric: names.join(",")) ] unless platform == "instagram"
      return [ { metric: names.join(","), metric_type: "total_value" } ] if scope == :media

      breakdown_names = names & INSTAGRAM_ACCOUNT_BREAKDOWNS.keys
      total_names = names & INSTAGRAM_ACCOUNT_TOTAL_METRICS
      time_series_names = names - breakdown_names - total_names
      queries = []
      queries << default_params.merge(metric: time_series_names.join(",")) if time_series_names.any?
      if total_names.any?
        queries << default_params.merge(metric: total_names.join(","), metric_type: "total_value")
      end
      breakdown_names.each do |name|
        queries << default_params.merge(
          metric: name,
          metric_type: "total_value",
          breakdown: INSTAGRAM_ACCOUNT_BREAKDOWNS.fetch(name)
        )
      end
      queries
    end

    def each_page(path, params:, follow_paging: true)
      response = @client.get(path, params: params)
      loop do
        Array(response["data"]).each do |row|
          return if yield(row) == :stop
        end
        break unless follow_paging

        next_url = response.dig("paging", "next")
        break if next_url.blank?

        response = @client.get(next_url)
      end
    end

    def numeric_value(value)
      return value if value.is_a?(Numeric)
      return BigDecimal(value) if value.is_a?(String) && value.match?(/\A-?\d+(?:\.\d+)?\z/)

      nil
    end

    def parse_time(value)
      Time.zone.parse(value.to_s) if value.present?
    end
  end
end
