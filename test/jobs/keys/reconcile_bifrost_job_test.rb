require "test_helper"

class Keys::ReconcileBifrostJobTest < ActiveSupport::TestCase
  setup do
    @bifrost = FakeBifrost.new
  end

  test "deactivates orphaned and revoked data-api virtual keys, reports missing ones, and leaves others alone" do
    live = issue_key(issuer: @bifrost.issuer).api_key
    revoked = issue_key(issuer: @bifrost.issuer).api_key
    revoked.update_columns(revoked_at: Time.current)
    missing = issue_key(issuer: @bifrost.issuer).api_key
    @bifrost.virtual_keys.delete(missing.bifrost_vk_id)
    orphan = @bifrost.add_virtual_key(name: "data-api:acct_999:key_999")
    other = @bifrost.add_virtual_key(name: "agent-42")

    Keys::ReconcileBifrostJob.perform_now(client: @bifrost.client)

    assert @bifrost.virtual_keys[live.bifrost_vk_id]["is_active"]
    refute @bifrost.virtual_keys[revoked.bifrost_vk_id]["is_active"]
    refute @bifrost.virtual_keys[orphan["id"]]["is_active"]
    assert @bifrost.virtual_keys[other["id"]]["is_active"], "non data-api keys are never touched"

    report = AuditEvent.where(action: "admin.bifrost_reconciled").recent.first.metadata
    assert_equal 3, report["checked"]
    assert_equal [ revoked.bifrost_vk_id, orphan["id"] ].sort, report["deactivated"].map { |row| row["vk_id"] }.sort
    assert_equal [ missing.id ], report["missing_in_bifrost"].map { |row| row["key_id"] }
  end

  test "keeps a suspended account's virtual keys active" do
    api_key = issue_key(issuer: @bifrost.issuer).api_key
    api_key.account.update!(suspended_at: Time.current)

    Keys::ReconcileBifrostJob.perform_now(client: @bifrost.client)

    assert @bifrost.virtual_keys[api_key.bifrost_vk_id]["is_active"]
  end

  test "skips when Bifrost isn't configured" do
    assert_no_difference -> { AuditEvent.count } do
      Keys::ReconcileBifrostJob.perform_now
    end
  end
end
