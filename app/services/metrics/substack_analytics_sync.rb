module Metrics
  class SubstackAnalyticsSync
    PAGE_SIZE = 15
    TRAFFIC_WINDOW_DAYS = 90
    TRAFFIC_REFRESH_DAYS = 7
    SNAPSHOT_ATTRIBUTES = %w[
      views cumulative_views opens opened open_rate clicks clicked click_through_rate
      delivered sent shares signups cumulative_signups subscribes cumulative_subscribes
      free_trials estimated_value engagement_rate downloads video_views video_minutes_watched
    ].freeze

    def initialize(client:, now: Time.current)
      @client = client
      @now = now
    end

    def sync_publication!(account_key:, url:)
      payload = @client.get("/api/v1/publication")
      publication = Metrics::SubstackPublication.find_or_initialize_by(account_key: account_key)
      publication.assign_attributes(
        publication_id: payload["id"]&.to_s,
        url: url,
        subdomain: URI.parse(url).host.to_s.split(".").first,
        name: payload["name"],
        last_synced_at: @now,
        source_payload: payload
      )
      publication.save!
      publication
    end

    def discover_recent_posts!(publication)
      offset = 0
      loop do
        result = discover_posts_page!(publication, offset: offset, stop_at_existing: true)
        break if result[:found_existing] || result[:next_offset].nil?

        offset = result[:next_offset]
      end
    end

    def discover_posts_page!(publication, offset:, stop_at_existing: false, backfill: false)
      payloads = Array(@client.get("/api/v1/archive", params: {
        sort: "new",
        offset: offset,
        limit: PAGE_SIZE
      }))
      known_ids = publication.posts.where(
        substack_post_id: payloads.filter_map { |payload| payload["id"]&.to_s }
      ).pluck(:substack_post_id).to_set
      found_existing = false
      processed = 0

      payloads.each do |payload|
        post_id = payload.fetch("id").to_s
        if stop_at_existing && known_ids.include?(post_id)
          upsert_post!(publication, payload)
          found_existing = true
          break
        end

        upsert_post!(publication, payload, initial_sync_at: backfill ? @now : nil)
        processed += 1
      end

      {
        found_existing: found_existing,
        next_offset: payloads.size == PAGE_SIZE ? offset + payloads.size : nil,
        processed: processed
      }
    end

    def sync_post_details!(post, scheduled_for:)
      response = @client.get(
        "/api/v1/post_management/detail/#{post.substack_post_id}",
        params: { offset: 0, limit: 1 }
      )
      details = Array(response["posts"]).first
      raise Metrics::SubstackClient::Error, "Substack returned no details for post #{post.substack_post_id}" unless details

      post.transaction do
        post.update!(details_payload: details, details_synced_at: @now)
        stats = details.fetch("stats", {})
        Array(stats["firstWeekDailyStats"]).each do |daily_stats|
          observed_at = parse_time(daily_stats["dt"])
          next unless observed_at

          upsert_snapshot!(
            post,
            snapshot_type: "first_week_daily",
            observed_at: observed_at,
            stats: daily_stats
          )
        end
        upsert_snapshot!(
          post,
          snapshot_type: "current",
          observed_at: scheduled_for,
          stats: stats.except("firstWeekDailyStats")
        )
      end
    end

    def sync_publication_traffic!(publication, start_date: nil, end_date: Date.current)
      end_date = end_date.to_date
      start_date ||= traffic_start_date(publication, end_date: end_date)
      return 0 unless start_date

      start_date = start_date.to_date
      return 0 if start_date > end_date

      rows = []
      window_start = start_date
      while window_start <= end_date
        window_end = [ window_start + TRAFFIC_WINDOW_DAYS - 1, end_date ].min
        rows.concat(fetch_daily_traffic_window(window_start, window_end))
        window_start = window_end + 1.day
      end

      Metrics::SubstackStat.transaction do
        rows.each do |row|
          stat = Metrics::SubstackStat.find_or_initialize_by(
            account: publication.account_key,
            date: row.fetch(:date)
          )
          stat.assign_attributes(
            views: row.fetch(:views),
            source: "substack_api",
            scraped_at: @now,
            source_payload: row.fetch(:source_payload)
          )
          stat.save!
        end
      end
      rows.size
    end

    private

    def traffic_start_date(publication, end_date:)
      earliest_post_date = publication.posts.where.not(published_at: nil).minimum(:published_at)&.to_date
      return unless earliest_post_date

      scope = Metrics::SubstackStat.for_account(publication.account_key)
      first_stored_date = scope.minimum(:date)
      last_stored_date = scope.maximum(:date)
      if first_stored_date.nil? || first_stored_date > earliest_post_date
        earliest_post_date
      else
        [ earliest_post_date, (last_stored_date || end_date) - TRAFFIC_REFRESH_DAYS ].max
      end
    end

    def fetch_daily_traffic_window(window_start, window_end)
      payload = @client.get(
        "/api/v1/publication/stats/publication_traffic/timeseries",
        params: {
          from: (window_start - 1).iso8601,
          to: window_end.iso8601,
          category: ""
        }
      )
      rows = Array(payload).map do |entry|
        unless entry.is_a?(Array) && entry.size >= 2
          raise Metrics::SubstackClient::Error, "Substack traffic returned an invalid row"
        end

        {
          date: Date.strptime(entry[0].to_s, "%Y/%m/%d"),
          views: Integer(entry[1]),
          source_payload: entry
        }
      rescue ArgumentError, TypeError
        raise Metrics::SubstackClient::Error, "Substack traffic returned an invalid daily row"
      end
      validate_daily_traffic!(rows, window_start: window_start, window_end: window_end)
      rows
    end

    def validate_daily_traffic!(rows, window_start:, window_end:)
      expected_dates = (window_start..window_end).to_a
      actual_dates = rows.map { |row| row.fetch(:date) }
      return if actual_dates == expected_dates

      raise Metrics::SubstackClient::Error,
        "Substack traffic was not daily for #{window_start}..#{window_end}"
    end

    def upsert_post!(publication, payload, initial_sync_at: nil)
      post = publication.posts.find_or_initialize_by(substack_post_id: payload.fetch("id").to_s)
      canonical_url = payload["canonical_url"].presence ||
        "#{publication.url.delete_suffix('/')}/p/#{payload['slug']}"
      post.assign_attributes(
        publication_id: payload["publication_id"]&.to_s,
        slug: payload["slug"],
        title: payload["title"],
        subtitle: payload["subtitle"],
        canonical_url: canonical_url,
        audience: payload["audience"],
        post_type: payload["type"] || payload["post_type"],
        cover_image_url: payload["cover_image"],
        published_at: parse_time(payload["post_date"]),
        published: payload.key?("is_published") ? payload["is_published"] == true : payload["post_date"].present?,
        feed_post: ::SubstackPost.find_by(external_url: canonical_url),
        source_payload: payload
      )
      post.save!
      if post.published?
        post.schedule_initial_details!(at: initial_sync_at || post.published_at || @now)
      end
      post
    end

    def upsert_snapshot!(post, snapshot_type:, observed_at:, stats:)
      snapshot = post.metric_snapshots.find_or_initialize_by(
        snapshot_type: snapshot_type,
        observed_at: observed_at
      )
      attributes = SNAPSHOT_ATTRIBUTES.index_with { |name| stats[name] }.symbolize_keys
      attributes[:day_number] = stats["day_n"]
      snapshot.assign_attributes(
        **attributes,
        scraped_at: @now,
        stats_payload: stats
      )
      snapshot.save!
      snapshot
    end

    def parse_time(value)
      Time.zone.parse(value.to_s) if value.present?
    end
  end
end
