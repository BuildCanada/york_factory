require "test_helper"

class Developers::KeysControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:member)
    post user_session_path, params: { email: @user.email, password: "password123" }
  end

  test "the old profile keys page redirects to the console" do
    get "/profile/api_keys"
    assert_redirected_to "/developers/keys"
  end

  test "overview shows the plan, the terms and a quickstart" do
    get developers_path

    assert_response :success
    assert_select "h2", text: /#{Regexp.escape(@user.name)}/
    assert_select ".card .value", text: "Free"
    assert_select "pre", text: /Authorization: Bearer/
    assert_select "button", text: "Accept the data terms"
  end

  test "creating a key shows its secret once, then only its prefix" do
    assert_difference -> { ApiKey.count }, 1 do
      post developers_keys_path, params: { api_key: { name: "Spending dashboard", scopes: %w[read:public usage:read], expiry: "90d" } }
    end

    assert_response :created
    raw = css_select(".api-key-secret").first.text.strip
    assert ApiKey::Token.well_formed?(raw)
    api_key = ApiKey.find_by_raw(raw)
    assert_equal "Spending dashboard", api_key.name
    assert_equal %w[read:public usage:read], api_key.scopes
    assert api_key.expires_at.between?(89.days.from_now, 91.days.from_now)

    get developers_key_path(api_key)
    assert_response :success
    assert_select ".api-key-secret", count: 0
    assert_no_match raw, response.body
    assert_select "dd", text: "#{api_key.token_prefix}…"
    assert_select "td", text: "key.created"

    get developers_keys_path
    assert_select "a", text: "Spending dashboard"
  end

  test "read:persons can't be chosen before the terms are accepted" do
    post developers_keys_path, params: { api_key: { name: "People", scopes: %w[read:public read:persons] } }
    assert_response :unprocessable_entity
    assert_select ".flash-alert", text: /read:persons needs the data terms/

    post developers_terms_path
    post developers_keys_path, params: { api_key: { name: "People", scopes: %w[read:public read:persons] } }
    assert_response :created
    assert AuditEvent.exists?(action: "account.terms_accepted")
  end

  test "with Bifrost down, creation fails cleanly and stores nothing" do
    bifrost = FakeBifrost.new
    bifrost.down!

    KeyIssuers.stub(:default, bifrost.issuer) do
      assert_no_difference -> { ApiKey.count } do
        post developers_keys_path, params: { api_key: { name: "Dashboard", scopes: %w[read:public] } }
      end
    end

    assert_response :service_unavailable
    assert_select ".flash-alert", text: /no key was created/
    assert_select ".api-key-secret", count: 0
  end

  test "rotating shows the new secret and keeps the old key for the grace period" do
    old = issue_key(user: @user, name: "Dashboard")

    post rotate_developers_key_path(old.api_key), params: { grace: "1h" }

    assert_response :created
    raw = css_select(".api-key-secret").first.text.strip
    refute_equal old.raw_key, raw
    assert_equal "rotating", old.api_key.reload.status
    assert_in_delta 1.hour.from_now, old.api_key.grace_until, 5.seconds
    assert ApiKey.find_by_raw(raw).usable?
  end

  test "revoking needs the key's name typed" do
    issued = issue_key(user: @user, name: "Dashboard")

    delete developers_key_path(issued.api_key), params: { confirm_name: "dash" }
    assert_redirected_to developers_key_path(issued.api_key)
    assert_nil issued.api_key.reload.revoked_at

    delete developers_key_path(issued.api_key), params: { confirm_name: "Dashboard" }
    assert_redirected_to developers_keys_path
    assert_equal "revoked", issued.api_key.reload.status
    assert_equal :revoked, Keys::Verify.call(issued.raw_key).error
  end

  test "renaming and widening scopes is audited" do
    issued = issue_key(user: @user, name: "Dashboard", scopes: %w[read:public])
    get new_developers_key_path
    assert_response :success
    get edit_developers_key_path(issued.api_key)
    assert_response :success
    assert_select "input[name='api_key[name]'][value='Dashboard']"

    patch developers_key_path(issued.api_key), params: { api_key: { name: "Dashboard v2", scopes: %w[read:public usage:read], allowed_ips: "203.0.113.0/24" } }

    assert_redirected_to developers_key_path(issued.api_key)
    issued.api_key.reload
    assert_equal "Dashboard v2", issued.api_key.name
    assert_equal [ "203.0.113.0/24" ], issued.api_key.allowed_ips
    assert AuditEvent.exists?(action: "key.updated", subject_id: issued.api_key.id)
    assert_equal [ "usage:read" ], AuditEvent.find_by!(action: "key.scopes_widened", subject_id: issued.api_key.id).metadata["added"]
  end

  test "a user can't see or change another account's keys" do
    other = issue_key(user: users(:regular), name: "Theirs")

    get developers_key_path(other.api_key)
    assert_response :not_found
    delete developers_key_path(other.api_key), params: { confirm_name: "Theirs" }
    assert_response :not_found
    post rotate_developers_key_path(other.api_key)
    assert_response :not_found
    assert other.api_key.reload.usable?
  end

  test "an organization member can see but not manage its keys" do
    org = Account.create!(name: "Newsroom", kind: "organization")
    org.memberships.create!(user: @user, role: "member")
    owner = users(:regular)
    org.memberships.create!(user: owner, role: "owner")
    issued = Keys::Issue.call(account: org, user: owner, name: "Shared", issuer: KeyIssuers::LocalIssuer.new, context: user_context(owner))

    post developers_account_switch_path, params: { account_id: org.id }
    get developers_keys_path
    assert_select "a", text: "Shared"

    delete developers_key_path(issued.api_key), params: { confirm_name: "Shared" }
    assert_redirected_to developers_keys_path
    assert issued.api_key.reload.usable?
  end

  test "unauthenticated visitors are sent to login" do
    delete destroy_user_session_path
    get developers_keys_path
    assert_redirected_to new_user_session_path
  end

  test "no raw key reaches the logs" do
    log = StringIO.new
    logger = ActiveSupport::Logger.new(log)
    logger.level = :debug
    Rails.logger.broadcast_to(logger)
    begin
      post developers_keys_path, params: { api_key: { name: "Logged?", scopes: %w[read:public cms:drafts] } }
      raw = css_select(".api-key-secret").first.text.strip
      api_key = ApiKey.find_by_raw(raw)
      post rotate_developers_key_path(api_key), params: { grace: "1h", key: raw }
      rotated_raw = css_select(".api-key-secret").first.text.strip
      get "/api/v1/me", params: { key: raw }, headers: { "Authorization" => "Bearer #{rotated_raw}" }
    ensure
      Rails.logger.stop_broadcasting_to(logger)
    end

    assert_includes log.string, "Developers::KeysController#create", "the test should capture request logs"
    refute_includes log.string, raw
    refute_includes log.string, rotated_raw
    refute_includes log.string, raw.delete_prefix("bc_stg_").rpartition("_").first, "not even the bare secret"
  end
end
