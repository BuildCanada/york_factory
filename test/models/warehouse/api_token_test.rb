require "test_helper"

class Warehouse::ApiTokenTest < ActiveSupport::TestCase
  test "issue! returns a raw token and stores only a hash" do
    raw = Warehouse::ApiToken.issue!(name: "issue-test-#{SecureRandom.hex(2)}", scopes: [ "kpis:read" ])
    assert_match(/\Ayfk_/, raw)
    record = Warehouse::ApiToken.find_by(name: "issue-test-#{raw[4, 4]}")
    # Note: raw token is not searchable; we search by name instead
    refute Warehouse::ApiToken.where(token_hash: raw).exists?
  end

  test "authenticate returns record for valid raw token" do
    name = "auth-test-#{SecureRandom.hex(2)}"
    raw = Warehouse::ApiToken.issue!(name: name, scopes: [ "kpis:write" ])
    record = Warehouse::ApiToken.authenticate(raw)
    assert record
    assert_equal name, record.name
    assert record.has_scope?("kpis:write")
  end

  test "authenticate rejects revoked tokens" do
    name = "rev-test-#{SecureRandom.hex(2)}"
    raw = Warehouse::ApiToken.issue!(name: name, scopes: [ "kpis:read" ])
    Warehouse::ApiToken.find_by!(name: name).update!(revoked_at: Time.current)
    assert_nil Warehouse::ApiToken.authenticate(raw)
  end

  test "authenticate rejects blank or wrong token" do
    assert_nil Warehouse::ApiToken.authenticate(nil)
    assert_nil Warehouse::ApiToken.authenticate("yfk_not-a-real-token")
  end

  test "rejects unknown scope" do
    t = Warehouse::ApiToken.new(name: "bad-#{SecureRandom.hex(2)}", token_hash: "h-#{SecureRandom.hex(4)}", scopes: [ "kpis:read", "evil" ])
    refute t.valid?
  end
end
