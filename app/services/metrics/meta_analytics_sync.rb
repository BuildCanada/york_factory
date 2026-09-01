module Metrics
  class MetaAnalyticsSync
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
      "follows_and_unfollows" => "follow_type",
      "views" => "media_product_type",
      "reach" => "media_product_type",
      "total_interactions" => "media_product_type"
    }.freeze
    INSTAGRAM_ACCOUNT_BREAKDOWN_METRICS = {
      "follows_and_unfollows" => {
        "FOLLOWER" => "follows",
        "NON_FOLLOWER" => "unfollows"
      }
    }.freeze
    INSTAGRAM_ACCOUNT_PAID_ORGANIC_METRICS = %w[views reach total_interactions].freeze
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

    # Instagram buckets account insights on the account's own calendar day, not UTC.
    # Meta reports that boundary back to us in the `end_time` of its time-series
    # metrics (e.g. reach), which lands on 07:00Z in August — midnight Pacific.
    # Override per account in credentials with `time_zone:` if an account differs.
    DEFAULT_INSIGHTS_TIME_ZONE = "America/Los_Angeles".freeze

    # Meta keeps revising a day's totals for a while after midnight, so each sync
    # re-requests a short trailing window. Re-requests upsert rather than insert.
    DEFAULT_SYNC_LOOKBACK_DAYS = 3

    def initialize(client:, now: Time.current, time_zone: DEFAULT_INSIGHTS_TIME_ZONE)
      @client = client
      @now = now
      @time_zone = ActiveSupport::TimeZone[time_zone.to_s] ||
        ActiveSupport::TimeZone[DEFAULT_INSIGHTS_TIME_ZONE]
    end

    # The most recent complete days in the account's timezone, newest last.
    def default_sync_days(count = DEFAULT_SYNC_LOOKBACK_DAYS)
      last_complete = @now.in_time_zone(@time_zone).to_date - 1
      ((last_complete - (count - 1))..last_complete).to_a
    end

    def sync!(platform:, account_key:, platform_account_id:, account_metrics: [], media_metrics: [], days: nil)
      account = sync_account!(
        platform: platform,
        account_key: account_key,
        platform_account_id: platform_account_id,
        account_metrics: account_metrics,
        days: days
      )
      discover_recent_media!(account)
      account
    end

    def sync_account!(platform:, account_key:, platform_account_id:, account_metrics: [], days: nil)
      validate_account!(platform, account_key)
      profile = @client.get(platform_account_id, params: {
        fields: ACCOUNT_FIELDS.fetch(platform).join(",")
      })
      account = upsert_account!(platform, account_key, platform_account_id, profile)
      sync_insights!(account.insights, platform_account_id, account_metrics,
        platform: platform, scope: :account, days: days || default_sync_days)
      account.update!(last_synced_at: @now)
      account
    end

    # Re-request a specific date range of account insights. Meta serves historical
    # account insights, so this recovers days that were never captured (or that were
    # captured with the old sync-clock timestamp).
    def backfill_account_insights!(account, metric_names:, from:, to:)
      days = (from.to_date..to.to_date).to_a
      return 0 if days.empty? || metric_names.blank?

      sync_insights!(account.insights, account.platform_account_id, metric_names,
        platform: account.platform, scope: :account, days: days)
      days.length
    end

    def discover_recent_media!(account)
      after = nil
      loop do
        result = discover_media_page!(account, after: after, stop_at_existing: true)
        break if result[:found_existing] || result[:next_cursor].blank?

        after = result[:next_cursor]
      end
    end

    def discover_media_page!(account, after: nil, stop_at_existing: false, backfill: false)
      params = {
        fields: MEDIA_FIELDS.fetch(account.platform).join(","),
        limit: 100
      }
      params[:after] = after if after.present?
      response = @client.get(
        "#{account.platform_account_id}/#{MEDIA_EDGE.fetch(account.platform)}",
        params: params
      )
      payloads = Array(response["data"])
      known_ids = account.media.where(platform_media_id: payloads.filter_map { |row| row["id"] }).
        pluck(:platform_media_id).to_set
      found_existing = false
      processed = 0

      payloads.each do |payload|
        if stop_at_existing && known_ids.include?(payload.fetch("id"))
          found_existing = true
          break
        end

        upsert_medium!(account, payload, initial_sync_at: backfill ? @now : nil)
        processed += 1
      end

      {
        found_existing: found_existing,
        next_cursor: response.dig("paging", "next").present? ?
          response.dig("paging", "cursors", "after") : nil,
        processed: processed
      }
    end

    def sync_media_insights!(medium, metric_names:)
      sync_insights!(medium.insights, medium.platform_media_id, metric_names,
        platform: medium.account.platform, scope: :media)
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

    def upsert_medium!(account, payload, initial_sync_at: nil)
      medium = account.media.find_or_initialize_by(platform_media_id: payload.fetch("id"))
      medium.assign_attributes(media_attributes(account.platform, payload))
      medium.save!
      medium.schedule_initial_insights!(at: initial_sync_at || medium.published_at || @now)
      medium
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

    def sync_insights!(association, object_id, metric_names, platform:, scope:, days: nil)
      return if metric_names.blank?

      insight_queries(platform, scope, metric_names, days: days).each do |query|
        each_page("#{object_id}/insights", params: query[:params], follow_paging: false) do |metric|
          sync_metric!(association, metric, day_observed_at: query[:observed_at])
        end
      end
    end

    def sync_metric!(association, metric, day_observed_at: nil)
        values = breakdown_values(metric)
        values = Array(metric["values"]) if values.empty?
        values = [ { "value" => metric["value"] } ] if values.empty? && metric.key?("value")
        if values.empty? && metric.key?("total_value") &&
            !INSTAGRAM_ACCOUNT_BREAKDOWNS.key?(metric["name"])
          total_value = metric["total_value"]
          value = total_value.is_a?(Hash) && total_value.key?("value") ? total_value["value"] : total_value
          values = [ { "value" => value } ]
        end
        association.klass.transaction do
          values.each do |value|
            # A total_value response carries no end_time. Without the requested day's
            # boundary it would fall back to the sync clock, which leaves the row
            # unattributable to a calendar day and defeats the uniqueness index.
            observed_at = parse_time(value["end_time"]) || day_observed_at || @now
            metric_name = value["normalized_metric_name"] || metric.fetch("name")
            insight = association.find_or_initialize_by(
              metric_name: metric_name,
              period: metric["period"],
              observed_at: observed_at
            )
            raw_value = value["value"]
            insight.assign_attributes(
              value_numeric: numeric_value(raw_value),
              value_payload: raw_value.is_a?(Hash) || raw_value.is_a?(Array) ? raw_value : {},
              source_payload: metric.merge("value_entry" => value.except("normalized_metric_name"))
            )
            insight.save!
          end

          reconcile_breakdown_siblings!(association, metric, values, day_observed_at)
        end
    end

    def reconcile_breakdown_siblings!(association, metric, values, day_observed_at)
      expected = normalized_sibling_names(metric["name"])
      return if expected.empty?

      observed_times = values.filter_map { |value| parse_time(value["end_time"]) }.uniq
      observed_times = [ day_observed_at || @now ] if observed_times.empty?
      present = values.filter_map { |value| value["normalized_metric_name"] }.uniq
      stale = expected - present
      observed_times.each do |observed_at|
        association.where(
          metric_name: stale,
          period: metric["period"],
          observed_at: observed_at
        ).delete_all if stale.any?

        # Older follows_and_unfollows rows stored the enclosing payload with no
        # numeric value. Its normalized siblings now fully replace that row.
        if INSTAGRAM_ACCOUNT_BREAKDOWN_METRICS.key?(metric["name"])
          association.where(
            metric_name: metric.fetch("name"),
            period: metric["period"],
            observed_at: observed_at
          ).delete_all
        end
      end
    end

    def normalized_sibling_names(metric_name)
      explicit = INSTAGRAM_ACCOUNT_BREAKDOWN_METRICS[metric_name]
      return explicit.values if explicit
      return [ "#{metric_name}_organic", "#{metric_name}_paid" ] if
        INSTAGRAM_ACCOUNT_PAID_ORGANIC_METRICS.include?(metric_name)

      []
    end

    def breakdown_values(metric)
      names = INSTAGRAM_ACCOUNT_BREAKDOWN_METRICS[metric["name"]]
      return paid_organic_values(metric) if INSTAGRAM_ACCOUNT_PAID_ORGANIC_METRICS.include?(metric["name"])
      return [] unless names

      Array(metric.dig("total_value", "breakdowns")).flat_map do |breakdown|
        Array(breakdown["results"]).filter_map do |result|
          dimension = Array(result["dimension_values"]).first
          normalized_name = names[dimension]
          next unless normalized_name

          {
            "value" => result["value"],
            "normalized_metric_name" => normalized_name,
            "dimension_values" => result["dimension_values"]
          }
        end
      end
    end

    def paid_organic_values(metric)
      total = metric.dig("total_value", "value")
      return [] if total.nil?

      results = Array(metric.dig("total_value", "breakdowns")).flat_map do |breakdown|
        Array(breakdown["results"])
      end
      return [ { "value" => total } ] if results.empty?

      paid = results.sum do |result|
        Array(result["dimension_values"]).include?("AD") ? result["value"].to_d : 0.to_d
      end
      organic = total.to_d - paid
      base_name = metric.fetch("name")
      [
        { "value" => total },
        { "value" => organic, "normalized_metric_name" => "#{base_name}_organic" },
        { "value" => paid, "normalized_metric_name" => "#{base_name}_paid" }
      ]
    end

    def insight_queries(platform, scope, metric_names, days: nil)
      names = metric_names.map(&:to_s)
      default_params = { period: "day" } if scope == :account
      default_params ||= {}
      unless platform == "instagram"
        return [ insight_query(default_params.merge(metric: names.join(","))) ]
      end
      if scope == :media
        return [ insight_query({ metric: names.join(","), metric_type: "total_value" }) ]
      end

      breakdown_names = names & INSTAGRAM_ACCOUNT_BREAKDOWNS.keys
      total_names = (names & INSTAGRAM_ACCOUNT_TOTAL_METRICS) - breakdown_names
      time_series_names = names - breakdown_names - total_names
      queries = []
      if time_series_names.any?
        # These come back with a real end_time per day, so they need no day scoping.
        queries << insight_query(default_params.merge(metric: time_series_names.join(",")))
      end

      # total_value metrics aggregate over the whole requested window and return no
      # end_time, so they must be requested one day at a time to keep a daily grain.
      (days.presence || default_sync_days).each do |day|
        window = day_window(day)
        observed_at = window.fetch(:observed_at)
        params = default_params.merge(since: window.fetch(:since), until: window.fetch(:until))
        if total_names.any?
          queries << insight_query(
            params.merge(metric: total_names.join(","), metric_type: "total_value"),
            observed_at: observed_at
          )
        end
        breakdown_names.each do |name|
          queries << insight_query(
            params.merge(
              metric: name,
              metric_type: "total_value",
              breakdown: INSTAGRAM_ACCOUNT_BREAKDOWNS.fetch(name)
            ),
            observed_at: observed_at
          )
        end
      end
      queries
    end

    def insight_query(params, observed_at: nil)
      { params: params, observed_at: observed_at }
    end

    # Meta stamps a day's time-series value with the *end* of that day, so a value
    # observed_at Aug 12 00:00 covers Aug 11. Day-scoped total_value rows follow the
    # same convention, which keeps both kinds of row on one timeline.
    def day_window(day)
      start_of_day = @time_zone.parse(day.to_date.to_s)
      end_of_day = start_of_day + 1.day
      # Meta treats an epoch `until` exactly on midnight as inclusive, despite the
      # equivalent YYYY-MM-DD boundary being exclusive. Stop one second short so
      # adjacent day requests never include the following day twice.
      { since: start_of_day.to_i, until: end_of_day.to_i - 1, observed_at: end_of_day }
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
