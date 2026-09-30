module Usage
  # The source of GET /v1/me/usage (PublicApi::Usage.source; design §6.3):
  # day buckets from usage_daily, hour buckets from usage_hourly (the last 7
  # days) and minute buckets from Analytics Engine (Usage::Live). The rollup
  # runs every minute over the last 2 hours, so today is about a minute
  # behind.
  class History
    STALE_AFTER = 10.minutes
    COUNTERS = %w[requests units cache_hits errors_4xx errors_5xx].freeze

    def initialize(live: Live.new, now: -> { Time.current })
      @live = live
      @now = now
    end

    # UsageBucket hashes oldest first (then by key and operation), after the
    # cursor key [bucket_start, key_id, operation], at most `limit`.
    def buckets(account:, granularity:, from:, to:, group_by:, limit:, after:)
      return [] unless account

      by_key = group_by.include?("key")
      by_operation = group_by.include?("operation")
      rows = if granularity == "minute"
        minutes(account:, from:, to:, group_by:, after:, limit:)
      else
        rolled_up(account:, granularity:, from:, to:, by_key:, by_operation:, after:, limit:)
      end
      rows.map { |row| serialize(row) }
    end

    def caveats(locale:, granularity:, from:, to:)
      notes = []
      latest = RollupRun.latest
      if granularity == "minute"
        notes << note(locale, :minute_unavailable) unless @live.configured?
      elsif latest.nil?
        notes << note(locale, :unrecorded)
      else
        notes << note(locale, :stale, time: latest.finished_at.utc.iso8601) if latest.finished_at < @now.call - STALE_AFTER && to > latest.window_end - 1.hour
        notes << note(locale, :hourly_retention) if granularity == "hour" && from < @now.call - HOURLY_RETENTION
      end
      notes
    end

    # One caveat, for PublicApi::Usage's older interface.
    def caveat(locale:) = caveats(locale:, granularity: "day", from: @now.call, to: @now.call).first

    TEXTS = {
      unrecorded: {
        "en" => "Usage history is not recorded yet: the metering rollup has not run, so no buckets are listed.",
        "fr" => "L'historique d'utilisation n'est pas encore enregistré : le cumul du comptage n'a pas encore été exécuté. Aucun intervalle n'est donc listé."
      },
      stale: {
        "en" => "Usage is rolled up to %{time}; later requests are not counted here yet.",
        "fr" => "L'utilisation est cumulée jusqu'à %{time}; les requêtes plus récentes ne sont pas encore comptées ici."
      },
      hourly_retention: {
        "en" => "Hour buckets are kept for 7 days; earlier hours are not listed. Use granularity=day for older usage.",
        "fr" => "Les intervalles horaires sont conservés 7 jours; les heures plus anciennes ne sont pas listées. Utilisez granularity=day pour l'utilisation plus ancienne."
      },
      minute_unavailable: {
        "en" => "Minute buckets come from live metering, which is not configured here, so none are listed.",
        "fr" => "Les intervalles par minute viennent du comptage en direct, qui n'est pas configuré ici. Aucun n'est donc listé."
      }
    }.freeze

    private

    def note(locale, code, **values)
      texts = TEXTS.fetch(code)
      PublicApi::Catalog.caveat(:coverage_partial, locale:, detail: Kernel.format(texts.fetch(locale.to_s) { texts.fetch("en") }, **values))
    end

    def rolled_up(account:, granularity:, from:, to:, by_key:, by_operation:, after:, limit:)
      daily = granularity == "day"
      table = daily ? "usage_daily" : "usage_hourly"
      bucket = daily ? "(t.day::timestamp AT TIME ZONE 'UTC')" : "t.hour_start"
      key = by_key ? "coalesce(t.api_key_id, 0)" : "0"
      operation = by_operation ? "t.operation" : "''"
      where = [ "t.account_id = :account", "#{bucket} >= :from", "#{bucket} < :to" ]
      values = { account: account.id, from:, to:, limit: }
      if after
        where << "(#{bucket}, #{key}, #{operation}) > (:after_bucket, :after_key, :after_operation)"
        values.merge!(after_bucket: Time.iso8601(after[0].to_s), after_key: after[1].to_s.delete_prefix("key_").to_i, after_operation: after[2].to_s)
      end
      sql = <<~SQL
        SELECT #{bucket} AS bucket_start, #{key} AS key_id, #{operation} AS operation,
          #{COUNTERS.map { |c| "sum(t.#{c})::bigint AS #{c}" }.join(', ')}
        FROM #{table} t WHERE #{where.join(' AND ')}
        GROUP BY 1, 2, 3 ORDER BY 1, 2, 3 LIMIT :limit
      SQL
      ApplicationRecord.connection.select_all(ApplicationRecord.sanitize_sql_array([ sql, values ])).map do |row|
        { bucket_start: row["bucket_start"], key_id: by_key && row["key_id"].to_i.positive? ? "key_#{row['key_id']}" : nil,
          operation: by_operation ? row["operation"] : nil, **COUNTERS.to_h { |c| [ c.to_sym, row[c].to_i ] } }
      end
    end

    def minutes(account:, from:, to:, group_by:, after:, limit:)
      rows = @live.minutes(account:, from:, to:, group_by:)
      if after
        cursor = [ Time.iso8601(after[0].to_s), after[1].to_s, after[2].to_s ]
        rows = rows.select { |b| ([ b[:bucket_start], b[:key_id].to_s, b[:operation].to_s ] <=> cursor).positive? }
      end
      rows.first(limit)
    end

    def serialize(row)
      start = row[:bucket_start]
      start = Time.find_zone("UTC").parse(start.to_s) unless start.respond_to?(:utc)
      { bucket_start: start.utc.iso8601, key_id: row[:key_id], operation: row[:operation], **COUNTERS.to_h { |c| [ c.to_sym, row[c.to_sym].to_i ] } }
    end
  end
end
