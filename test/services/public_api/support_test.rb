require "test_helper"

# The public API's building blocks: the rate limiter, cursors, as_of,
# formatting, parameter checks and fact-factory's name normalization.
class PublicApiSupportTest < ActiveSupport::TestCase
  Caller = Data.define(:api_key, :account, :plan) do
    def anonymous? = api_key.nil?
  end

  def anonymous = Caller.new(api_key: nil, account: nil, plan: Plan.fetch("anonymous"))

  test "the limiter counts units in minute and daily windows, and refuses without taking" do
    store = ActiveSupport::Cache::MemoryStore.new
    now = Time.utc(2026, 9, 29, 12, 0, 10)
    limiter = PublicApi::RateLimiter.new(store:, now:)
    charge = limiter.charge(caller: anonymous, ip: "192.0.2.1", units: 29)
    assert charge.result.allowed
    assert_equal [ 1, 50, 971 ], [ charge.result.minute_remaining, charge.result.minute_reset, charge.result.allowance_remaining ]
    refused = limiter.charge(caller: anonymous, ip: "192.0.2.1", units: 2)
    refute refused.result.allowed
    assert_equal "rate_limited", refused.result.code
    assert_equal 1, limiter.charge(caller: anonymous, ip: "192.0.2.1", units: 1).result.minute_used - 29
    assert_equal 30, limiter.allowance_used(caller: anonymous, ip: "192.0.2.1")
    assert limiter.charge(caller: anonymous, ip: "192.0.2.2", units: 30).result.allowed, "per IP"
  end

  test "settling a charge gives back what the response did not cost" do
    store = ActiveSupport::Cache::MemoryStore.new
    limiter = PublicApi::RateLimiter.new(store:, now: Time.utc(2026, 9, 29, 12, 0, 0))
    charge = limiter.charge(caller: anonymous, ip: "192.0.2.1", units: 5)
    settled = limiter.settle(charge, units: 0, rate_units: 1)
    assert_equal [ 1, 0 ], [ settled.minute_used, settled.allowance_used ]
    assert_equal 0, limiter.allowance_used(caller: anonymous, ip: "192.0.2.1")
  end

  test "the store is cache, memory or off" do
    assert_same Rails.cache, PublicApi::RateLimiter.build_store("cache")
    assert_kind_of ActiveSupport::Cache::MemoryStore, PublicApi::RateLimiter.build_store("memory")
    assert_nil PublicApi::RateLimiter.build_store("off")
    assert_kind_of ActiveSupport::Cache::MemoryStore, PublicApi::RateLimiter.build_store(nil), "the test cache is a null store"
    assert_raises(ArgumentError) { PublicApi::RateLimiter.build_store("redis") }
  end

  test "cursors are signed and carry their release, keys and parameters" do
    cursor = PublicApi::Cursor.encode(release: 11, keys: [ "a", nil ], fingerprint: "f")
    assert_operator cursor.size, :<=, 512
    decoded = PublicApi::Cursor.decode(cursor)
    assert_equal [ 11, [ "a", nil ], "f" ], [ decoded.release, decoded.keys, decoded.fingerprint ]
    version, payload, signature = cursor.split(".")
    forged = Base64.urlsafe_encode64({ r: 10, k: [ "a" ], f: "f" }.to_json, padding: false)
    assert_raises(PublicApi::Cursor::Invalid) { PublicApi::Cursor.decode([ version, forged, signature ].join(".")) }
    assert_raises(PublicApi::Cursor::Invalid) { PublicApi::Cursor.decode("c1.#{payload}") }
    assert_raises(PublicApi::Cursor::Invalid) { PublicApi::Cursor.decode("garbage") }
  end

  test "as_of resolves numbers, dates and timestamps, and says which are pinned" do
    releases = [ 10, 11 ].map { |n| PublicApi::AsOf::ServedRelease.new(number: n, published_at: Time.utc(2026, 9, n == 10 ? 20 : 27)) }
    now = Time.utc(2026, 9, 29)
    resolve = ->(v) { PublicApi::AsOf.resolve(v, releases:, now:) }
    assert_equal [ 11, false ], resolve.(nil).then { |r| [ r.release, r.pinned ] }
    assert_equal [ 10, true ], resolve.("10").then { |r| [ r.release, r.pinned ] }
    assert_equal 10, resolve.("2026-09-26").release
    assert_equal 11, resolve.("2026-09-27T00:00:00Z").release
    assert_equal 11, resolve.("2026-09-27T01:00:00+01:00").release
    refute resolve.("2026-10-01").pinned, "a future time can still move"
    assert_equal "not_yet_published", assert_raises(PublicApi::Problem) { resolve.("2026-09-19") }.code
    assert_equal "not_found", assert_raises(PublicApi::Problem) { resolve.("12") }.code
    assert_equal "release_building", assert_raises(PublicApi::Problem) { PublicApi::AsOf.resolve(nil, releases: []) }.code
  end

  test "amounts, fiscal years and FSAs are written as the contract says" do
    assert_equal "125000.00", PublicApi::Format.amount(BigDecimal("125000"))
    assert_equal "1.2345", PublicApi::Format.amount("1.234500")
    assert_equal "-0.50", PublicApi::Format.amount(-0.5)
    assert_equal "0.123457", PublicApi::Format.amount("0.1234567")
    assert_equal "2024-25", PublicApi::Format.fiscal_year(2024)
    assert_equal "1999-00", PublicApi::Format.fiscal_year(1999)
    assert_equal 2024, PublicApi::Format.fiscal_year_start("2024-25")
    assert_nil PublicApi::Format.fiscal_year_start("2024-26")
    assert_equal "T2P", PublicApi::Format.fsa("t2p 1j9")
    assert_equal({ "a" => { "b" => [ {} ] } }, PublicApi::Format.without_address_keys({ "a" => { "b" => [ { "StreetAddress" => 1 } ], "address" => 2 } }))
  end

  test "request IDs are req_ and a ULID" do
    assert_match(/\Areq_[0-9A-HJKMNP-TV-Z]{26}\z/, PublicApi::RequestId.generate)
    assert_operator PublicApi::RequestId.ulid(now: Time.utc(2026, 9, 29)), :<, PublicApi::RequestId.ulid(now: Time.utc(2026, 9, 30))
  end

  test "parameters are checked against the contract, all at once" do
    op = PublicApi::Spec.operation("listSpending")
    parsed = PublicApi::Parameters.parse(op, query: { "source" => "proactive_grants,transfer_payments", "limit" => "10", "latest_revision_only" => "true" }, path: {})
    assert_equal [ %w[proactive_grants transfer_payments], 10, true, "id" ], parsed.values.values_at("source", "limit", "latest_revision_only", "sort")
    error = assert_raises(PublicApi::Problem) do
      PublicApi::Parameters.parse(op, query: { "source" => "nope", "limit" => "0", "latest_revision_only" => "yes", "x" => "1" }, path: {})
    end
    assert_equal %w[latest_revision_only limit source x], error.extra[:errors].map { |e| e[:parameter] }.sort
  end

  test "names normalize as fact-factory's names.py does" do
    JSON.parse(file_fixture("fact_factory_names.json").read).each do |name, normalized, key|
      assert_equal [ normalized, key ], [ FactFactory::Names.normalize(name), FactFactory::Names.match_key(name) ], name
    end
  end

  test "the read model connection refuses writes, in Rails and in the database" do
    assert_raises(ActiveRecord::ReadOnlyError, ActiveRecord::ReadOnlyRecord) { FactFactory::Release.first.update!(build_seconds: 1) }
    error = assert_raises(ActiveRecord::StatementInvalid, ActiveRecord::ReadOnlyError) do
      FactFactoryRecord.connection.raw_connection.exec("DELETE FROM api.releases")
    rescue PG::ReadOnlySqlTransaction => e
      raise ActiveRecord::StatementInvalid, e.message
    end
    assert_match(/read-only/, error.message)
  end
end
