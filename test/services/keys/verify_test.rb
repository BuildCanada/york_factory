require "test_helper"

class Keys::VerifyTest < ActiveSupport::TestCase
  setup do
    @issued = issue_key(scopes: %w[read:public usage:read])
    @raw = @issued.raw_key
  end

  test "verifies a key and returns its caller" do
    result = Keys::Verify.call(@raw, scopes: [ "read:public" ], ip: "203.0.113.7")

    assert result.ok?
    assert_equal @issued.api_key, result.caller.api_key
    assert_equal %w[read:public usage:read], result.caller.scopes
    assert_equal "free", result.caller.plan.name
    assert_equal "203.0.113.7", @issued.api_key.reload.last_used_ip.to_s
  end

  test "a missing scope is insufficient_scope, naming the scope" do
    result = Keys::Verify.call(@raw, scopes: [ "cms:drafts" ])

    assert_equal :insufficient_scope, result.error
    assert_equal "cms:drafts", result.required_scope
  end

  test "a mistyped key is malformed and costs no query" do
    queries = count_queries { assert_equal :malformed, Keys::Verify.call(mistyped(@raw)).error }

    assert_equal 0, queries
  end

  test "unknown, missing, expired and suspended keys fail" do
    assert_equal :missing, Keys::Verify.call(nil).error
    assert_equal :unknown, Keys::Verify.call(ApiKey::Token.wrap(SecureRandom.alphanumeric(40))).error
    assert_equal :expired, Keys::Verify.call(@raw, now: 2.years.from_now).error

    @issued.api_key.account.update!(suspended_at: Time.current)
    assert_equal :suspended, Keys::Verify.call(@raw).error
  end

  test "IP and origin restrictions are enforced" do
    issued = issue_key(allowed_ips: [ "203.0.113.0/24" ], allowed_origins: [ "https://example.com" ])

    assert Keys::Verify.call(issued.raw_key, ip: "203.0.113.1", origin: "https://example.com").ok?
    assert_equal :ip_not_allowed, Keys::Verify.call(issued.raw_key, ip: "198.51.100.1", origin: "https://example.com").error
    assert_equal :origin_not_allowed, Keys::Verify.call(issued.raw_key, ip: "203.0.113.1", origin: "https://evil.example").error
  end

  private

  def count_queries(&)
    count = 0
    counter = ->(*, payload) { count += 1 unless payload[:name].in?([ "SCHEMA", "TRANSACTION" ]) }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &)
    count
  end
end
