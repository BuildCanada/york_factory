module Usage
  # What the developer console shows (design §4.4): units by day, by
  # operation, errors and 429s, for an account or one of its keys, from the
  # rollup tables.
  class Report
    Day = Data.define(:day, :requests, :units, :errors_4xx, :errors_5xx, :throttled) do
      def errors = errors_4xx + errors_5xx
    end
    Operation = Data.define(:operation, :requests, :units, :errors, :throttled)

    attr_reader :account, :api_key

    def initialize(account:, api_key: nil, now: Time.current)
      @account = account
      @api_key = api_key
      @now = now.utc
    end

    # One Day per UTC day of the last `days`, today included, zeros filled in.
    def daily(days: 30)
      first = @now.to_date - (days - 1)
      found = scope(Daily).where(day: first..@now.to_date).group(:day)
        .pluck(:day, *Daily::COUNTERS.map { |c| Arel.sql("sum(#{c})") }).index_by(&:first)
      (first..@now.to_date).map do |day|
        row = found[day] || [ day, 0, 0, 0, 0, 0, 0 ]
        Day.new(day:, requests: row[1].to_i, units: row[2].to_i, errors_4xx: row[4].to_i, errors_5xx: row[5].to_i, throttled: row[6].to_i)
      end
    end

    # Units by hour over the last `hours` (at most 7 days), zeros filled in.
    def hourly(hours: 48)
      first = @now.beginning_of_hour - (hours - 1).hours
      found = scope(Hourly).where(hour_start: first..).group(:hour_start).sum(:units).transform_keys { |t| t.utc }
      (0...hours).map { |i| first + i.hours }.map { |hour| [ hour, found.fetch(hour, 0).to_i ] }
    end

    # The top operations by units over the last `days`.
    def operations(days: 30, limit: 10)
      scope(Daily).where(day: (@now.to_date - (days - 1))..)
        .group(:operation).order(Arel.sql("sum(units) DESC"), :operation).limit(limit)
        .pluck(:operation, Arel.sql("sum(requests)"), Arel.sql("sum(units)"), Arel.sql("sum(errors_4xx) + sum(errors_5xx)"), Arel.sql("sum(throttled)"))
        .map { |op, requests, units, errors, throttled| Operation.new(operation: op, requests: requests.to_i, units: units.to_i, errors: errors.to_i, throttled: throttled.to_i) }
    end

    # {api_key_id => units} over the last 24 hours, for the keys table's sparkline.
    def self.key_hours(account, now: Time.current)
      first = now.utc.beginning_of_hour - 23.hours
      rows = Hourly.where(account:, hour_start: first..).where.not(api_key_id: nil).group(:api_key_id, :hour_start).sum(:units)
      rows.each_with_object(Hash.new { |h, k| h[k] = Array.new(24, 0) }) do |((key_id, hour), units), out|
        index = ((hour.utc - first) / 1.hour).to_i
        out[key_id][index] = units.to_i if index.between?(0, 23)
      end
    end

    def freshness = RollupRun.latest&.finished_at

    private

    def scope(model)
      rows = model.where(account_id: account.id)
      api_key ? rows.where(api_key_id: api_key.id) : rows
    end
  end
end
