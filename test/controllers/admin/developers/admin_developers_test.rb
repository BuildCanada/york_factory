require "test_helper"

class Admin::DevelopersTest < ActionDispatch::IntegrationTest
  include AdminTestHelper

  setup do
    @issued = issue_key(user: users(:member), name: "Member key")
    @account = @issued.api_key.account
  end

  test "members can't reach the admin view" do
    post user_session_path, params: { email: users(:member).email, password: "password123" }
    get admin_developers_root_path
    assert_redirected_to new_user_session_path
  end

  test "admins see the overview, accounts, keys and audit log" do
    sign_in_admin

    get admin_developers_root_path
    assert_response :success
    assert_select "h2", text: "Bifrost reconciliation"

    get admin_developers_accounts_path(q: users(:member).email)
    assert_response :success
    assert_select "a", text: @account.name

    get admin_developers_account_path(@account)
    assert_response :success
    assert_select "td", text: users(:member).email

    get admin_developers_keys_path(prefix: @issued.api_key.token_prefix)
    assert_response :success
    assert_select "td", text: "Member key"

    get admin_developers_audit_events_path(action_prefix: "key.")
    assert_response :success
    assert_select "td", text: "key.created"

    get admin_developers_audit_events_path(format: :csv, account_id: @account.id)
    assert_response :success
    assert_match(/key\.created/, response.body)
  end

  test "suspending an account stops its keys and is audited" do
    sign_in_admin

    post suspend_admin_developers_account_path(@account), params: { reason: "Scraping persons" }

    assert_redirected_to admin_developers_account_path(@account)
    assert @account.reload.suspended?
    assert_equal :suspended, Keys::Verify.call(@issued.raw_key).error
    event = AuditEvent.find_by!(action: "admin.account_suspended", account_id: @account.id)
    assert_equal "admin", event.actor_kind
    assert_equal users(:admin), event.actor_user

    post unsuspend_admin_developers_account_path(@account)
    assert Keys::Verify.call(@issued.raw_key).ok?
    assert AuditEvent.exists?(action: "admin.account_unsuspended", account_id: @account.id)
  end

  test "a suspension needs a reason" do
    sign_in_admin
    post suspend_admin_developers_account_path(@account), params: { reason: " " }
    refute @account.reload.suspended?
  end

  test "admins can override a plan with an expiry" do
    sign_in_admin

    patch admin_developers_account_path(@account), params: { account: { plan: "free", plan_override: "partner", plan_override_expires_at: 30.days.from_now.iso8601 } }

    assert_redirected_to admin_developers_account_path(@account)
    assert_equal "partner", @account.reload.effective_plan_name
    assert AuditEvent.exists?(action: "admin.plan_changed", account_id: @account.id)
  end

  test "admins can revoke any key as leaked" do
    sign_in_admin

    post revoke_admin_developers_key_path(@issued.api_key), params: { reason: "leak" }

    assert_equal "revoked", @issued.api_key.reload.status
    assert_equal "leak", @issued.api_key.revoked_reason
    assert AuditEvent.exists?(action: "key.revoked.leak", subject_id: @issued.api_key.id)
  end

  test "only superadmins can start a mass rotation, with confirmation" do
    sign_in_admin
    post admin_developers_mass_rotation_path, params: { reason: "drill", confirm: "ROTATE ALL" }
    assert_no_enqueued_jobs(only: Keys::MassRotateJob)

    delete destroy_user_session_path
    post user_session_path, params: { email: users(:superadmin).email, password: "password123" }
    post admin_developers_mass_rotation_path, params: { reason: "drill", confirm: "nope" }
    assert_no_enqueued_jobs(only: Keys::MassRotateJob)

    assert_enqueued_with(job: Keys::MassRotateJob) do
      post admin_developers_mass_rotation_path, params: { reason: "drill", confirm: "ROTATE ALL" }
    end
  end
end
