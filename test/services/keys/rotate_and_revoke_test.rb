require "test_helper"

class Keys::RotateAndRevokeTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @bifrost = FakeBifrost.new
    @user = users(:member)
    @original = issue_key(user: @user, name: "dashboard", issuer: @bifrost.issuer, allowed_ips: [ "203.0.113.0/24" ])
  end

  test "rotation issues a key with the same settings and keeps the old one for the grace period" do
    old_key = @original.api_key
    result = Keys::Rotate.call(api_key: old_key, user: @user, grace: "24h", issuer: @bifrost.issuer, context: user_context(@user))

    assert result.ok?
    new_key = result.api_key
    assert_equal "dashboard", new_key.name
    assert_equal old_key.scopes, new_key.scopes
    assert_equal old_key.allowed_ips, new_key.allowed_ips
    assert_equal old_key, new_key.rotated_from
    refute_equal old_key.bifrost_vk_id, new_key.bifrost_vk_id

    old_key.reload
    assert_equal "rotating", old_key.status
    assert_in_delta 24.hours.from_now, old_key.grace_until, 5.seconds
    assert Keys::Verify.call(@original.raw_key, ip: "203.0.113.5").ok?
    assert Keys::Verify.call(result.raw_key, ip: "203.0.113.5").ok?
    assert_equal :expired, Keys::Verify.call(@original.raw_key, ip: "203.0.113.5", now: 25.hours.from_now).error
    assert AuditEvent.exists?(action: "key.rotated", subject_id: old_key.id)
    assert AuditEvent.exists?(action: "key.rotated_in", subject_id: new_key.id)

    assert_raises(Keys::Rotate::NotRotatable) do
      Keys::Rotate.call(api_key: old_key, user: @user, issuer: @bifrost.issuer, context: user_context(@user))
    end
  end

  test "rotation with no grace revokes the old key at once" do
    result = Keys::Rotate.call(api_key: @original.api_key, user: @user, grace: "none", issuer: @bifrost.issuer, context: user_context(@user))

    assert result.ok?
    assert_equal "revoked", @original.api_key.reload.status
    assert_equal "rotated", @original.api_key.revoked_reason
    assert_equal :revoked, Keys::Verify.call(@original.raw_key).error
  end

  test "rotation with Bifrost down leaves the old key untouched" do
    @bifrost.down!

    assert_no_difference -> { ApiKey.count } do
      result = Keys::Rotate.call(api_key: @original.api_key, user: @user, issuer: @bifrost.issuer, context: user_context(@user))
      refute result.ok?
    end
    assert_nil @original.api_key.reload.grace_until
    assert_equal "active", @original.api_key.status
  end

  test "revoking stops the key and deactivates its Bifrost virtual key" do
    api_key = @original.api_key
    with_bifrost_issuer do
      assert Keys::Revoke.call(api_key:, reason: "user", context: user_context(@user))
    end

    assert_equal "revoked", api_key.reload.status
    assert_equal :revoked, Keys::Verify.call(@original.raw_key).error
    assert_equal false, @bifrost.virtual_keys.fetch(api_key.bifrost_vk_id)["is_active"]
    assert AuditEvent.exists?(action: "key.revoked", subject_id: api_key.id)
    refute Keys::Revoke.call(api_key:, reason: "user", context: user_context(@user)), "revoking twice is a no-op"
  end

  test "revoking with Bifrost down still revokes, and retries the deactivation later" do
    @bifrost.down!
    api_key = @original.api_key

    with_bifrost_issuer do
      assert_enqueued_with(job: ApiKey::DeactivateInBifrostJob) do
        Keys::Revoke.call(api_key:, reason: "user", context: user_context(@user))
      end
    end
    assert_equal "revoked", api_key.reload.status

    @bifrost.up!
    with_bifrost_issuer { perform_enqueued_jobs(only: ApiKey::DeactivateInBifrostJob) }
    assert_equal false, @bifrost.virtual_keys.fetch(api_key.bifrost_vk_id)["is_active"]
  end

  test "a leaked key is audited as such" do
    Keys::Revoke.call(api_key: @original.api_key, reason: "leak", context: system_context)

    assert AuditEvent.exists?(action: "key.revoked.leak", subject_id: @original.api_key.id)
  end

  private

  # ApiKey#deactivate_in_bifrost! builds its own BifrostIssuer; point it at the fake.
  def with_bifrost_issuer(&)
    fake = @bifrost.issuer
    KeyIssuers::BifrostIssuer.stub(:new, fake, &)
  end
end
