require "test_helper"

class ApiKeyTest < ActiveSupport::TestCase
  test "issue returns the raw key once and stores only its digest" do
    api_key, raw = ApiKey.issue!(user: users(:admin), name: "memo agent")

    assert raw.start_with?(ApiKey::TOKEN_PREFIX)
    refute_equal raw, api_key.token_digest
    assert_equal api_key, ApiKey.authenticate(raw)
    assert api_key.reload.last_used_at.present?
  end

  test "authentication uses the owner's current permissions and rejects revoked keys" do
    api_key, raw = ApiKey.issue!(user: users(:member), name: "temporary")
    users(:member).update!(role: :admin)

    assert ApiKey.authenticate(raw).user.admin?
    api_key.revoke!
    assert_nil ApiKey.authenticate(raw)
  end

  test "revoked? mirrors the revoked_at state" do
    api_key, = ApiKey.issue!(user: users(:admin), name: "revocable")

    refute api_key.revoked?
    api_key.revoke!
    assert api_key.revoked?
  end
end
