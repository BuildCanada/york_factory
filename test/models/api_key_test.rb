require "test_helper"

class ApiKeyTest < ActiveSupport::TestCase
  test "issue! returns a bc_ key once and stores only its peppered digest" do
    api_key, raw = ApiKey.issue!(user: users(:admin), name: "memo agent")

    assert_match(/\Abc_stg_[A-Za-z0-9]{40}_[0-9A-Za-z]{6}\z/, raw)
    assert ApiKey::Token.well_formed?(raw)
    assert_equal ApiKey::Token.digest(raw), api_key.token_digest
    refute_equal ApiKey::Token.legacy_digest(raw), api_key.token_digest
    assert_equal raw.first(12), api_key.token_prefix
    assert_equal [ "cms:drafts" ], api_key.scopes
    assert_equal "local", api_key.issuer
    assert_equal api_key, ApiKey.authenticate(raw)
    assert api_key.reload.last_used_at.present?
  end

  test "the digest uses the pepper, not secret_key_base" do
    raw = "bc_stg_#{'a' * 32}"
    with_env("API_KEY_PEPPER" => "pepper-one") do
      @one = ApiKey::Token.digest(raw)
    end
    with_env("API_KEY_PEPPER" => "pepper-two") do
      @two = ApiKey::Token.digest(raw)
    end

    refute_equal @one, @two
    refute_equal ApiKey::Token.legacy_digest(raw), @one
  end

  test "a mistyped key fails its checksum" do
    raw = ApiKey::Token.wrap("4fQ9m2VxR7tLp0aZkE3sW8yN1bH6cJ5d")

    assert ApiKey::Token.well_formed?(raw)
    refute ApiKey::Token.well_formed?(raw.sub("4fQ9", "4fQ8"))
    refute ApiKey::Token.well_formed?(raw.chop)
    refute ApiKey::Token.well_formed?("bc_live_short_abcdef")
    refute ApiKey::Token.well_formed?("sk-bf-#{SecureRandom.uuid}")
  end

  test "wraps Bifrost's secret, including its hyphens" do
    secret = SecureRandom.uuid
    raw = ApiKey::Token.wrap(secret, prefix: ApiKey::Token::LIVE_PREFIX)

    assert raw.start_with?("bc_live_#{secret}_")
    assert ApiKey::Token.well_formed?(raw)
    assert_raises(ApiKey::Token::InvalidSecret) { ApiKey::Token.wrap("has spaces in it and more") }
  end

  test "authentication uses the owner's current permissions and rejects revoked keys" do
    api_key, raw = ApiKey.issue!(user: users(:member), name: "temporary")
    users(:member).update!(role: :admin)

    assert ApiKey.authenticate(raw).user.admin?
    Keys::Revoke.call(api_key:, reason: "user", context: system_context)
    assert_nil ApiKey.authenticate(raw)
  end

  test "CMS authentication needs the cms:drafts scope" do
    raw = issue_key(scopes: %w[read:public]).raw_key

    assert_nil ApiKey.authenticate(raw)
  end

  test "legacy yfu_ keys keep working and move to the peppered digest on first use" do
    raw = "yfu_#{SecureRandom.urlsafe_base64(32)}"
    account = Account.personal_for!(users(:member))
    api_key = ApiKey.create!(user: users(:member), account:, name: "draft-memo agent", scopes: [ "cms:drafts" ],
      token_digest: ApiKey::Token.legacy_digest(raw), token_prefix: raw.first(12))

    assert_equal api_key, ApiKey.authenticate(raw)
    assert_equal ApiKey::Token.digest(raw), api_key.reload.token_digest
    assert_equal api_key, ApiKey.authenticate(raw)
  end

  test "status follows revocation, expiry, rotation grace and account suspension" do
    api_key = issue_key.api_key

    assert_equal "active", api_key.status
    api_key.update!(grace_until: 1.hour.from_now)
    assert_equal "rotating", api_key.status
    assert api_key.usable?
    assert_equal "expired", api_key.status(2.hours.from_now)
    api_key.update!(grace_until: nil, expires_at: 1.minute.ago)
    assert_equal "expired", api_key.status
    api_key.update!(expires_at: nil)
    api_key.account.update!(suspended_at: Time.current)
    assert_equal "suspended", api_key.reload.status
    refute api_key.usable?
  end

  test "names are unique among an account's live keys only" do
    first = issue_key(name: "dashboard").api_key
    duplicate = first.account.api_keys.new(user: first.user, name: "dashboard", scopes: [ "read:public" ], token_digest: "x", token_prefix: "x")
    refute duplicate.valid?

    first.update!(grace_until: 1.day.from_now)
    assert duplicate.valid?, duplicate.errors.full_messages.to_sentence
  end

  test "rejects unknown and reserved scopes" do
    api_key = issue_key.api_key
    api_key.scopes = %w[read:public keys:manage]

    refute api_key.valid?
    assert_match(/keys:manage/, api_key.errors[:scopes].to_sentence)
  end

  test "IP and origin restrictions" do
    api_key = issue_key(allowed_ips: [ "203.0.113.0/24" ], allowed_origins: [ "https://Example.com/" ]).api_key

    assert_equal [ "https://example.com" ], api_key.allowed_origins
    assert api_key.ip_allowed?("203.0.113.40")
    refute api_key.ip_allowed?("198.51.100.1")
    refute api_key.ip_allowed?(nil)
    assert api_key.origin_allowed?("https://example.com")
    refute api_key.origin_allowed?("https://evil.example")
    refute api_key.origin_allowed?(nil)

    api_key.allowed_ips = [ "not-an-ip" ]
    refute api_key.valid?
  end

  test "records last use at most once a minute" do
    api_key = issue_key.api_key
    now = Time.current

    api_key.record_use!(ip: "203.0.113.1", at: now)
    assert_equal "203.0.113.1", api_key.reload.last_used_ip.to_s
    api_key.record_use!(ip: "203.0.113.2", at: now + 30.seconds)
    assert_equal "203.0.113.1", api_key.reload.last_used_ip.to_s
    api_key.record_use!(ip: "203.0.113.3", at: now + 61.seconds)
    assert_equal "203.0.113.3", api_key.reload.last_used_ip.to_s
  end

  test "lookup payload carries the edge contract fields" do
    api_key = issue_key(scopes: %w[read:public usage:read]).api_key
    payload = api_key.lookup_payload

    assert_equal %i[key_id account_id plan scopes status expires_at grace_until allowed_origins allowed_ips limits].sort, payload.keys.sort
    assert_equal "free", payload[:plan]
    assert_equal({ rate: 120, burst: 240, monthly: 100_000 }, payload[:limits])
    assert_equal "active", payload[:status]
  end

  private

  def with_env(values)
    previous = values.to_h { |k, _| [ k, ENV[k] ] }
    values.each { |k, v| ENV[k] = v }
    yield
  ensure
    previous.each { |k, v| ENV[k] = v }
  end
end
