module Usage
  # Usage by minute, straight from Analytics Engine (design §6.3, "Live"):
  # for GET /v1/me/usage?granularity=minute and the key detail page. A few
  # seconds behind the edge. Cached for CACHE_TTL so a page refresh doesn't
  # query Analytics Engine again.
  class Live
    CACHE_TTL = 10.seconds

    def initialize(client: AnalyticsEngineClient.new, cache: Rails.cache)
      @client = client
      @cache = cache
    end

    def configured? = @client.configured?

    # [{bucket_start:, key_id:, operation:, requests:, units:, cache_hits:,
    # errors_4xx:, errors_5xx:, throttled:}] per minute in [from, to), oldest
    # first, for an account (and one key when given), split by key and/or
    # operation. Empty when Analytics Engine isn't configured or fails.
    def minutes(account:, from:, to:, api_key: nil, group_by: [])
      return [] unless configured? && account

      by_key = group_by.include?("key")
      by_operation = group_by.include?("operation")
      key = [ "usage-live", account.id, api_key&.id, from.to_i, to.to_i, by_key, by_operation ].join(":")
      @cache.fetch(key, expires_in: CACHE_TTL) do
        rows = @client.query(sql(account:, api_key:, from:, to:, by_key:, by_operation:))
        rows.map { |row| bucket(row, by_key:, by_operation:) }.sort_by { |b| [ b[:bucket_start], b[:key_id].to_s, b[:operation].to_s ] }
      end
    rescue AnalyticsEngineClient::Error => error
      Rails.logger.warn("[Usage::Live] #{error.message}")
      []
    end

    private

    def sql(account:, api_key:, from:, to:, by_key:, by_operation:)
      columns = [ "toStartOfMinute(timestamp) AS minute" ]
      columns << "blob2 AS key_id" if by_key
      columns << "blob3 AS operation" if by_operation
      groups = [ "minute", (by_key ? "key_id" : nil), (by_operation ? "operation" : nil) ].compact
      key_filter = api_key ? " AND blob2 = '#{Integer(api_key.id)}'" : ""
      <<~SQL
        SELECT #{columns.join(', ')},
          SUM(_sample_interval) AS requests, SUM(_sample_interval * double1) AS units,
          SUM(IF(blob5 = 'hit', _sample_interval, 0)) AS cache_hits,
          SUM(IF(blob4 = '4xx', _sample_interval, 0)) AS errors_4xx,
          SUM(IF(blob4 = '5xx', _sample_interval, 0)) AS errors_5xx,
          SUM(IF(double4 = 429, _sample_interval, 0)) AS throttled
        FROM #{@client.dataset}
        WHERE timestamp >= #{AnalyticsEngineClient.time(from)} AND timestamp < #{AnalyticsEngineClient.time(to)}
          AND blob1 = '#{Integer(account.id)}'#{key_filter}
        GROUP BY #{groups.join(', ')}
      SQL
    end

    def bucket(row, by_key:, by_operation:)
      key_id = by_key && row["key_id"].to_s.match?(/\A\d+\z/) ? "key_#{row['key_id']}" : nil
      {
        bucket_start: Time.find_zone("UTC").parse(row["minute"].to_s).utc,
        key_id:,
        operation: by_operation ? row["operation"].presence : nil,
        **Rollup::COUNTERS.to_h { |c| [ c.to_sym, row[c].to_f.round ] }
      }
    end
  end
end
