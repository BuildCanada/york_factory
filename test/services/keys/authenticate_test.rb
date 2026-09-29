require "test_helper"

# One principal (Keys::Caller) for API keys and OAuth tokens, as the REST
# API and the MCP server see them.
class Keys::AuthenticateTest < ActiveSupport::TestCase
  MCP = "http://www.example.com/mcp".freeze
  REST = "http://www.example.com/v1".freeze

  setup do
    @user = users(:member)
    @account = Account.personal_for!(@user)
    @app = Doorkeeper::Application.create!(name: "Client", redirect_uri: "https://client.example/cb", confidential: false,
      client_type: "dynamic", scopes: Oauth::Settings::SCOPES.join(" "))
  end

  def token(scopes: "read:public usage:read", resource: MCP, account: @account, **attributes)
    Doorkeeper::AccessToken.create!(application: @app, resource_owner_id: @user.id, scopes:, resource:, account_id: account&.id,
      expires_in: 3600, **attributes)
  end

  test "an API key is an :api_key principal" do
    issued = issue_key(user: @user, scopes: %w[read:public usage:read])
    result = Keys::Authenticate.call(issued.raw_key, resource: MCP, scopes: [ "read:public" ])
    assert result.ok?
    caller = result.caller
    assert_equal :api_key, caller.kind
    assert_equal issued.api_key, caller.api_key
    assert_equal @account, caller.account
    assert_equal @user, caller.user
    assert caller.scope?("usage:read")
  end

  test "an OAuth token is an :oauth principal with its account, user and scopes" do
    access = token
    result = Keys::Authenticate.call(access.token, resource: MCP, scopes: [ "read:public" ])
    assert result.ok?
    caller = result.caller
    assert_equal :oauth, caller.kind
    assert caller.oauth?
    assert_equal access, caller.oauth_token
    assert_equal @app, caller.oauth_application
    assert_equal @account, caller.account
    assert_equal @user, caller.user
    assert_equal %w[read:public usage:read], caller.scopes
    assert_equal "free", caller.plan.name
  end

  test "a token for another resource is refused" do
    assert_equal :wrong_audience, Keys::Authenticate.call(token.token, resource: REST).error
    assert_equal :wrong_audience, Keys::Authenticate.call(token(resource: nil).token, resource: MCP).error
  end

  test "missing scopes are reported together" do
    result = Keys::Authenticate.call(token(scopes: "usage:read").token, resource: MCP, scopes: %w[read:public read:persons])
    assert_equal :insufficient_scope, result.error
    assert_equal %w[read:public read:persons], result.missing_scopes
    assert_equal :oauth, result.caller.kind
  end

  test "read:persons counts only while the account may hold it" do
    access = token(scopes: "read:public read:persons")
    assert_not Keys::Authenticate.call(access.token, resource: MCP).caller.scope?("read:persons")

    @account.update!(terms_accepted_at: Time.current)
    assert Keys::Authenticate.call(access.token, resource: MCP).caller.scope?("read:persons")
  end

  test "revoked, expired, unknown and orphaned tokens are refused" do
    assert_equal :token_revoked, Keys::Authenticate.call(token.tap(&:revoke).token, resource: MCP).error
    assert_equal :token_expired, Keys::Authenticate.call(token(created_at: 2.hours.ago).token, resource: MCP).error
    assert_equal :invalid_token, Keys::Authenticate.call("not-a-token", resource: MCP).error
    assert_equal :missing, Keys::Authenticate.call("", resource: MCP).error

    other = Account.create!(name: "Not mine", kind: "organization", plan: "free")
    assert_equal :invalid_token, Keys::Authenticate.call(token(account: other).token, resource: MCP).error
    assert_equal :invalid_token, Keys::Authenticate.call(token(account: nil).token, resource: MCP).error
  end

  test "a bc_ key with a bad checksum is a key error, never an OAuth lookup" do
    issued = issue_key(user: @user)
    assert_equal :malformed, Keys::Authenticate.call(mistyped(issued.raw_key), resource: MCP).error
  end
end
