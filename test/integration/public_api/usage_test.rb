require "test_helper"

# GET /v1/me/usage against the contract (getUsage), from the rollup tables
# and, for minutes, Analytics Engine.
class PublicApiUsageTest < PublicApiTestCase
  setup do
    @issued = issue_key(scopes: %w[read:public usage:read])
    @key = @issued.api_key
    @account = @key.account
    @other = issue_key(scopes: %w[read:public]).api_key
    @today = Time.current.utc.to_date
    Usage::RollupRun.create!(window_start: 2.hours.ago, window_end: 1.hour.from_now, source: "analytics_engine", finished_at: 1.minute.ago)
  end

  teardown { PublicApi::Usage.source = nil }

  def daily(day, units, key: @key, operation: "getEntity", account: key&.account || @account, **counters)
    Usage::Daily.create!(account:, api_key_id: key&.id, operation:, day:, units:, requests: units, rolled_up_at: Time.current, **counters)
  end

  def usage(**params) = api_get("/v1/me/usage", key: @issued.raw_key, **params)

  test "day buckets from usage_daily: the account's own, summed, oldest first" do
    daily(@today - 2, 10, cache_hits: 4, errors_4xx: 1)
    daily(@today - 2, 5, operation: "searchEntities")
    daily(@today - 2, 7, key: @other)
    daily(@today - 2, 3, key: nil)
    daily(@today, 2)
    other_account = issue_key(user: users(:admin)).api_key
    daily(@today, 999, key: other_account)

    usage
    assert_conforms("getUsage", status: 200)
    assert_equal [ [ "#{(@today - 2).iso8601}T00:00:00Z", 25, 25, 4, 1 ], [ "#{@today.iso8601}T00:00:00Z", 2, 2, 0, 0 ] ],
      body["data"].map { |b| b.values_at("bucket_start", "units", "requests", "cache_hits", "errors_4xx") }
    assert(body["data"].all? { |b| b["key_id"].nil? && b["operation"].nil? })
    assert_empty body.dig("meta", "caveats")
    assert_equal "private, no-store", response.headers["Cache-Control"]
  end

  test "group_by key and operation, paged with a cursor" do
    daily(@today - 1, 10)
    daily(@today - 1, 5, operation: "searchEntities")
    daily(@today - 1, 7, key: @other)
    daily(@today - 1, 3, key: nil)
    daily(@today, 2)

    seen = []
    cursor = nil
    loop do
      usage(group_by: "key,operation", limit: 2, **(cursor ? { cursor: } : {}))
      assert_conforms("getUsage", status: 200)
      seen.concat(body["data"].map { |b| b.values_at("key_id", "operation", "units") })
      cursor = next_cursor or break
    end
    ids = [ @key.id, @other.id ].sort
    unit_for = { @key.id => [ [ "getEntity", 10 ], [ "searchEntities", 5 ] ], @other.id => [ [ "getEntity", 7 ] ] }
    expected = [ [ nil, "getEntity", 3 ] ] + ids.flat_map { |id| unit_for[id].map { |op, u| [ "key_#{id}", op, u ] } } + [ [ "key_#{@key.id}", "getEntity", 2 ] ]
    assert_equal expected, seen

    usage(group_by: "operation")
    assert_equal [ [ "getEntity", 20 ], [ "searchEntities", 5 ], [ "getEntity", 2 ] ], body["data"].map { |b| b.values_at("operation", "units") }
  end

  test "hour buckets from usage_hourly, with a caveat past the 7 days kept" do
    hour = Time.current.utc.beginning_of_hour - 3.hours
    Usage::Hourly.create!(account: @account, api_key_id: @key.id, operation: "getEntity", hour_start: hour, units: 4, requests: 4, rolled_up_at: Time.current)
    usage(granularity: "hour")
    assert_conforms("getUsage", status: 200)
    assert_equal [ [ hour.iso8601, 4 ] ], body["data"].map { |b| b.values_at("bucket_start", "units") }
    assert_empty body.dig("meta", "caveats")

    usage(granularity: "hour", from: 10.days.ago.utc.iso8601)
    assert_conforms("getUsage", status: 200)
    assert_equal [ "coverage_partial" ], body.dig("meta", "caveats").map { |c| c["code"] }
    assert_match(/kept for 7 days/, body.dig("meta", "caveats", 0, "text"))
  end

  test "minute buckets come live from Analytics Engine" do
    ae = FakeAnalyticsEngine.new
    minute = Time.current.utc.beginning_of_minute - 5.minutes
    ae.write(account_id: @account.id, key_id: @key.id, at: minute + 10.seconds, units: 2, count: 3, cache: "hit")
    ae.write(account_id: @account.id, key_id: @key.id, at: minute + 70.seconds, status: 503, units: 0)
    PublicApi::Usage.source = Usage::History.new(live: Usage::Live.new(client: ae.client, cache: ActiveSupport::Cache::NullStore.new))

    usage(granularity: "minute", group_by: "key")
    assert_conforms("getUsage", status: 200)
    assert_equal [ [ minute.iso8601, "key_#{@key.id}", 6, 3, 3, 0 ], [ (minute + 1.minute).iso8601, "key_#{@key.id}", 0, 1, 0, 1 ] ],
      body["data"].map { |b| b.values_at("bucket_start", "key_id", "units", "requests", "cache_hits", "errors_5xx") }
    assert_includes ae.queries.last[:sql], "blob1 = '#{@account.id}'"

    usage(granularity: "minute", limit: 1)
    assert_equal 1, body["data"].size
    usage(granularity: "minute", limit: 1, cursor: next_cursor)
    assert_conforms("getUsage", status: 200)
    assert_equal [ (minute + 1.minute).iso8601 ], body["data"].map { |b| b["bucket_start"] }
  end

  test "caveats: no rollup yet, a stale rollup, no live metering" do
    Usage::RollupRun.delete_all
    usage
    assert_conforms("getUsage", status: 200)
    assert_match(/not recorded yet/, body.dig("meta", "caveats", 0, "text"))

    Usage::RollupRun.create!(window_start: 3.hours.ago, window_end: 1.hour.ago, source: "analytics_engine", finished_at: 90.minutes.ago)
    usage
    assert_match(/rolled up to/, body.dig("meta", "caveats", 0, "text"))

    usage(granularity: "minute")
    assert_conforms("getUsage", status: 200)
    assert_match(/live metering, which is not configured/, body.dig("meta", "caveats", 0, "text"))
  end

  test "/v1/me counts this month's rolled-up units" do
    daily(@today, 4_321)
    with_env("PUBLIC_API_RATE_LIMIT_STORE" => "off") do
      api_get "/v1/me", key: @issued.raw_key
    end
    assert_conforms("getMe", status: 200)
    assert_equal 4_321, body.dig("data", "limits", "monthly_units_used")
  end
end
