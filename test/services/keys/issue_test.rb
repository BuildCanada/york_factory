require "test_helper"

class Keys::IssueTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include ActionMailer::TestHelper

  setup do
    @bifrost = FakeBifrost.new
    @user = users(:member)
    @account = Account.personal_for!(@user)
  end

  test "issues through Bifrost with empty provider configs and stores only the digest" do
    result = issue(scopes: %w[read:public usage:read])

    assert result.ok?
    api_key = result.api_key
    vk = @bifrost.virtual_keys.fetch(api_key.bifrost_vk_id)
    assert_equal [], vk["provider_configs"]
    assert_equal "data-api:acct_#{@account.id}:key_#{api_key.id}", vk["name"]
    assert_equal "bc_stg_#{vk['value'].delete_prefix('sk-bf-')}", result.raw_key.rpartition("_").first
    assert_equal ApiKey::Token.digest(result.raw_key), api_key.reload.token_digest
    assert_equal "bifrost", api_key.issuer
    refute ApiKey.where(token_digest: result.raw_key).exists?
    assert api_key.expires_at.between?(364.days.from_now, 366.days.from_now)
    assert_equal api_key, Keys::Verify.call(result.raw_key, scopes: [ "read:public" ]).api_key

    event = AuditEvent.find_by!(action: "key.created", subject_id: api_key.id)
    assert_equal @account.id, event.account_id
    assert_equal @user, event.actor_user
    refute_includes event.metadata.to_json, result.raw_key
  end

  test "creates one Bifrost customer per account" do
    issue(name: "one")
    issue(name: "two")

    assert_equal 1, @bifrost.customers.size
    assert_equal @bifrost.customers.keys.first, @account.reload.bifrost_customer_id
    assert_equal [ @account.bifrost_customer_id ], @bifrost.virtual_keys.values.map { |vk| vk["customer_id"] }.uniq
  end

  test "with Bifrost down, issuing fails cleanly and stores nothing" do
    @bifrost.down!

    assert_no_difference -> { ApiKey.count } do
      assert_no_difference -> { AuditEvent.count } do
        result = issue
        refute result.ok?
        assert_nil result.raw_key
        assert_includes result.api_key.errors[:base], Keys::Issue::UNAVAILABLE_MESSAGE
        refute result.api_key.persisted?
      end
    end
  end

  test "an unexpected virtual key value fails closed and deactivates the virtual key" do
    http = Class.new(FakeBifrost) do
      def request(method, url, **options)
        response = super
        return response unless method == "POST" && url.end_with?("/virtual-keys")

        body = JSON.parse(response.body)
        body["virtual_key"]["value"] = "unexpected-format"
        virtual_keys[body["virtual_key"]["id"]]["value"] = "unexpected-format"
        FakeBifrost::Response.new(status: 200, body: JSON.generate(body))
      end
    end.new

    assert_no_difference -> { ApiKey.count } do
      refute Keys::Issue.call(account: @account, user: @user, name: "x", issuer: http.issuer, context: user_context(@user)).ok?
    end
    assert_equal [ false ], http.virtual_keys.values.map { |vk| vk["is_active"] }
  end

  test "validates before calling Bifrost" do
    result = issue(name: "", scopes: %w[read:public])

    refute result.ok?
    assert result.api_key.errors[:name].any?
    assert_empty @bifrost.requests
  end

  test "enforces the plan's key limit" do
    5.times { |i| issue(name: "key #{i}", issuer: KeyIssuers::LocalIssuer.new) }
    result = issue(name: "one too many")

    refute result.ok?
    assert_match(/allows 5 active keys/, result.api_key.errors[:base].to_sentence)
  end

  test "read:persons is not a scope" do
    refute issue(scopes: %w[read:public read:persons]).ok?
    refute_includes Keys::Policy.new(@account, @user).grantable_scopes, "read:persons"
  end

  test "a suspended account can't issue keys" do
    @account.update!(suspended_at: Time.current, suspended_reason: "abuse")

    result = issue
    refute result.ok?
    assert_match(/suspended: abuse/, result.api_key.errors[:base].to_sentence)
  end

  test "emails the account owners without the key" do
    result = nil
    assert_enqueued_emails 1 do
      result = issue
    end
    perform_enqueued_jobs
    mail = ActionMailer::Base.deliveries.last
    assert_equal [ @user.email ], mail.to
    refute_includes mail.body.to_s, result.raw_key
    assert_includes mail.body.to_s, result.api_key.token_prefix
  end

  private

  def issue(name: "key #{SecureRandom.hex(2)}", scopes: ApiKey::DEFAULT_SCOPES, issuer: @bifrost.issuer)
    Keys::Issue.call(account: @account, user: @user, name:, scopes:, issuer:, context: user_context(@user))
  end
end
