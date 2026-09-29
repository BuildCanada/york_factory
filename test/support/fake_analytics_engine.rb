# An in-memory stand-in for Cloudflare Analytics Engine's SQL API, injected
# into AnalyticsEngineClient as its HTTP transport. It holds points as the
# edge Worker writes them (data-api workers/edge/src/meter.ts) and answers
# the two queries york_factory sends, the hourly rollup (Usage::Rollup) and
# the per-minute live query (Usage::Live), by aggregating them the way the
# SQL says. Counts come back as strings, as Analytics Engine returns 64-bit
# integers in JSON. Tests never call Cloudflare.
class FakeAnalyticsEngine
  Response = Data.define(:status, :body)
  Point = Data.define(:account_id, :key_id, :operation, :at, :units, :status, :cache, :latency, :sample)

  attr_reader :queries, :points
  attr_accessor :fail_with

  def initialize
    @points = []
    @queries = []
    @fail_with = nil
  end

  def client = AnalyticsEngineClient.new(account_id: "cf-account", api_token: "cf-token", dataset: "data_api_requests", http: self)

  def write(account_id:, at:, key_id: nil, operation: "getEntity", units: 1, status: 200, cache: "miss", latency: 12.0, sample: 1, count: 1)
    count.times do
      @points << Point.new(account_id: account_id.to_s, key_id: key_id.to_s, operation:, at: at.utc, units:, status:, cache:, latency:, sample:)
    end
  end

  def request(method, url, headers:, body:)
    @queries << { method:, url:, headers:, sql: body }
    return Response.new(status: @fail_with, body: "{}") if @fail_with

    Response.new(status: 200, body: JSON.generate({ "meta" => [], "data" => answer(body), "rows" => 0 }))
  end

  private

  def answer(sql)
    from, to = sql.scan(/toDateTime\('([^']+)'\)/).flatten.map { |t| Time.find_zone("UTC").parse(t) }
    selected = @points.select { |p| p.at >= from && p.at < to }
    if (account = sql[/blob1 = '(\d+)'/, 1])
      selected = selected.select { |p| p.account_id == account }
      key = sql[/blob2 = '(\d+)'/, 1]
      selected = selected.select { |p| p.key_id == key } if key
      by_key = sql.include?("blob2 AS key_id")
      by_operation = sql.include?("blob3 AS operation")
      groups = selected.group_by { |p| [ p.at.beginning_of_minute, by_key ? p.key_id : nil, by_operation ? p.operation : nil ] }
      groups.map do |(minute, key_id, operation), points|
        row = { "minute" => minute.strftime("%Y-%m-%d %H:%M:%S") }
        row["key_id"] = key_id if by_key
        row["operation"] = operation if by_operation
        row.merge(totals(points))
      end
    else
      selected = selected.reject { |p| p.account_id.empty? }
      selected.group_by { |p| [ p.account_id, p.key_id, p.operation, p.at.beginning_of_hour ] }.map do |(account_id, key_id, operation, hour), points|
        { "account_id" => account_id, "key_id" => key_id, "operation" => operation, "hour" => hour.strftime("%Y-%m-%d %H:%M:%S"),
          **totals(points), "p95_ms" => points.map(&:latency).max }
      end
    end
  end

  def totals(points)
    weight = ->(&block) { points.sum { |p| block.call(p) ? p.sample : 0 }.to_s }
    {
      "requests" => points.sum(&:sample).to_s,
      "units" => points.sum { |p| p.sample * p.units }.to_s,
      "cache_hits" => weight.call { |p| p.cache == "hit" },
      "errors_4xx" => weight.call { |p| p.status.between?(400, 499) },
      "errors_5xx" => weight.call { |p| p.status >= 500 },
      "throttled" => weight.call { |p| p.status == 429 }
    }
  end
end
