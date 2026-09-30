require "test_helper"

class AccountTest < ActiveSupport::TestCase
  test "personal_for! creates one personal account with an owner membership" do
    account = Account.personal_for!(users(:member))

    assert account.personal?
    assert_equal "free", account.plan
    assert account.memberships.find_by(user: users(:member)).owner?
    assert_equal account, Account.personal_for!(users(:member))
  end

  test "staff get the internal plan" do
    assert_equal "internal", Account.personal_for!(users(:admin)).plan
  end

  test "a plan override applies until it expires" do
    account = Account.personal_for!(users(:member))
    account.update!(plan_override: "partner", plan_override_expires_at: 1.day.from_now)
    assert_equal "partner", account.effective_plan_name
    assert_equal 20, account.plan_definition.key_limit

    account.update!(plan_override_expires_at: 1.minute.ago)
    assert_equal "free", account.effective_plan_name
  end

  test "the audit log is append-only in the database" do
    event = AuditEvent.record!("key.created", context: AuditEvent::Context.system, metadata: { name: "x" })

    assert event.readonly?
    assert_raises(ActiveRecord::StatementInvalid) { AuditEvent.where(id: event.id).update_all(action: "tampered") }
  end

  test "the audit log refuses deletes" do
    event = AuditEvent.record!("key.created", context: AuditEvent::Context.system)

    assert_raises(ActiveRecord::StatementInvalid) { AuditEvent.where(id: event.id).delete_all }
  end
end
