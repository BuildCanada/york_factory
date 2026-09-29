module Usage
  # Re-aggregates the edge's Analytics Engine points into usage_hourly and
  # usage_daily (docs/public-interface-design.md §6.3).
  #
  # Each run replaces every hour of its window with what Analytics Engine
  # holds for it now, then rebuilds each day the window touches from the
  # hourly rows. So a run is idempotent (running it twice gives the same
  # rows), and a point that reaches Analytics Engine late is counted by the
  # next run whose window covers its hour. Two schedules share this code:
  # every minute over RECENT (the console stays about a minute behind), and
  # hourly over LATE (late points; Analytics Engine keeps 3 months).
  #
  # Anonymous points (no account) are not rolled up: they have no owner to
  # show them to or bill. OAuth points have an account and no key.
  class Rollup
    RECENT = 2.hours
    LATE = 48.hours
    LOCK = 7_302_119_101
    OPERATION = /\A[A-Za-z0-9_.:-]{1,100}\z/
    COUNTERS = %w[requests units cache_hits errors_4xx errors_5xx throttled].freeze

    Result = Data.define(:window_start, :window_end, :hourly_rows, :daily_rows, :skipped)

    def initialize(client: AnalyticsEngineClient.new, now: Time.current)
      @client = client
      @now = now.utc
    end

    def configured? = @client.configured?

    # Returns a Result, or nil when Analytics Engine isn't configured.
    def run!(window: LATE)
      return nil unless configured?

      window_start = (@now - window).beginning_of_hour
      window_end = @now.beginning_of_hour + 1.hour
      hours, skipped = normalize(@client.query(sql(window_start, window_end)))
      daily_rows = 0

      ApplicationRecord.transaction do
        ApplicationRecord.connection.execute("SELECT pg_advisory_xact_lock(#{LOCK})")
        Hourly.where(hour_start: window_start...window_end).delete_all
        Hourly.insert_all(hours) if hours.any?
        daily_rows = rebuild_days(window_start.to_date, (window_end - 1.second).to_date)
        Hourly.where(hour_start: ...(@now - HOURLY_RETENTION)).delete_all
        RollupRun.create!(window_start:, window_end:, source: "analytics_engine", hourly_rows: hours.size, daily_rows:, finished_at: Time.current)
      end
      Result.new(window_start:, window_end:, hourly_rows: hours.size, daily_rows:, skipped:)
    end

    # The Analytics Engine query: the WS-H contract's columns (blob1
    # account_id, blob2 key_id, blob3 operation, blob4 status class, blob5
    # cache, double1 units, double2 latency) plus double4, the HTTP status.
    # _sample_interval weights each point, as Analytics Engine samples.
    def sql(from, to)
      <<~SQL
        SELECT blob1 AS account_id, blob2 AS key_id, blob3 AS operation, toStartOfHour(timestamp) AS hour,
          SUM(_sample_interval) AS requests, SUM(_sample_interval * double1) AS units,
          SUM(IF(blob5 = 'hit', _sample_interval, 0)) AS cache_hits,
          SUM(IF(blob4 = '4xx', _sample_interval, 0)) AS errors_4xx,
          SUM(IF(blob4 = '5xx', _sample_interval, 0)) AS errors_5xx,
          SUM(IF(double4 = 429, _sample_interval, 0)) AS throttled,
          quantileWeighted(0.95)(double2, _sample_interval) AS p95_ms
        FROM #{@client.dataset}
        WHERE timestamp >= #{AnalyticsEngineClient.time(from)} AND timestamp < #{AnalyticsEngineClient.time(to)} AND blob1 != ''
        GROUP BY account_id, key_id, operation, hour
      SQL
    end

    private

    # Rows to insert, merged by group, and the number of points' groups left
    # out (an account this app doesn't have, or a malformed row).
    def normalize(rows)
      account_ids = Account.where(id: rows.filter_map { |r| integer(r["account_id"]) }.uniq).pluck(:id).to_set
      skipped = 0
      merged = {}
      rows.each do |row|
        account_id = integer(row["account_id"])
        hour = parse_hour(row["hour"])
        unless account_id && account_ids.include?(account_id) && hour
          skipped += 1
          next
        end

        operation = row["operation"].to_s.match?(OPERATION) ? row["operation"].to_s : "unknown"
        group = [ account_id, integer(row["key_id"]), operation, hour ]
        entry = merged[group] ||= { account_id:, api_key_id: group[1], operation:, hour_start: hour, p95_ms: nil, rolled_up_at: @now,
                                    **COUNTERS.to_h { |c| [ c.to_sym, 0 ] } }
        COUNTERS.each { |c| entry[c.to_sym] += row[c].to_f.round }
        p95 = row["p95_ms"]&.to_f
        entry[:p95_ms] = [ entry[:p95_ms], p95 ].compact.max if p95&.finite?
      end
      [ merged.values, skipped ]
    end

    def rebuild_days(first, last)
      days = first..last
      Daily.where(day: days).delete_all
      sums = COUNTERS.map { |c| "sum(#{c})" }.join(", ")
      sql = <<~SQL
        INSERT INTO usage_daily (account_id, api_key_id, operation, day, #{COUNTERS.join(', ')}, rolled_up_at)
        SELECT account_id, api_key_id, operation, (hour_start AT TIME ZONE 'UTC')::date, #{sums}, :now
        FROM usage_hourly WHERE hour_start >= :from AND hour_start < :to
        GROUP BY account_id, api_key_id, operation, (hour_start AT TIME ZONE 'UTC')::date
      SQL
      from = first.in_time_zone("UTC")
      to = (last + 1).in_time_zone("UTC")
      ApplicationRecord.connection.exec_update(ApplicationRecord.sanitize_sql_array([ sql, { now: @now, from:, to: } ]))
    end

    def integer(value)
      value.to_s.match?(/\A[1-9]\d{0,18}\z/) ? value.to_i : nil
    end

    def parse_hour(value)
      time = value.is_a?(Numeric) ? Time.at(value) : Time.find_zone("UTC").parse(value.to_s)
      time&.utc&.beginning_of_hour
    rescue ArgumentError
      nil
    end
  end
end
