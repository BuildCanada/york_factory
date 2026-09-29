require "test_helper"

# The developer console's list of authorized OAuth clients, with revoke.
class Developers::AuthorizedAppsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @member = users(:member)
    @account = Account.personal_for!(@member)
    @app = Doorkeeper::Application.create!(name: "Claude", redirect_uri: "https://claude.ai/api/mcp/auth_callback", confidential: false,
      client_type: "metadata_document", uid: "https://claude.ai/oauth/mcp-client-metadata.json",
      metadata_url: "https://claude.ai/oauth/mcp-client-metadata.json", scopes: Oauth::Settings::SCOPES.join(" "))
    @token = Doorkeeper::AccessToken.create!(application: @app, resource_owner_id: @member.id, account_id: @account.id,
      resource: "http://www.example.com/mcp", scopes: "read:public usage:read", expires_in: 3600, use_refresh_token: true)
    sign_in_user(@member)
  end

  test "lists authorized apps with their scopes and resource" do
    get developers_authorized_apps_path
    assert_response :success
    assert_match "Claude", response.body
    assert_match "claude.ai", response.body
    assert_match "read:public usage:read", response.body
    assert_match "http://www.example.com/mcp", response.body
  end

  test "an app whose access has lapsed isn't listed" do
    @token.update_columns(created_at: 31.days.ago)
    get developers_authorized_apps_path
    assert_match "No apps are authorized", response.body
  end

  test "revoking stops the app's tokens at once and is audited" do
    access = @token.token
    delete developers_authorized_app_path(@app)
    assert_redirected_to developers_authorized_apps_path
    assert @token.reload.revoked?

    mcp_call(access)
    assert_response :unauthorized
    event = AuditEvent.find_by!(action: "oauth.authorization_revoked", subject: @app)
    assert_equal @account.id, event.account_id
    assert_equal @member, event.actor_user
    assert_equal 1, event.metadata["tokens_revoked"]
  end

  test "a member can't revoke another member's authorization of an organization account" do
    org = Account.create!(name: "Newsroom", kind: "organization", plan: "free")
    org.memberships.create!(user: @member, role: "member")
    other = users(:regular)
    org.memberships.create!(user: other, role: "owner")
    theirs = Doorkeeper::AccessToken.create!(application: @app, resource_owner_id: other.id, account_id: org.id,
      resource: "http://www.example.com/mcp", scopes: "read:public", expires_in: 3600)
    post developers_account_switch_path, params: { account_id: org.id }

    get developers_authorized_apps_path
    assert_match "Claude", response.body
    assert_no_match ">Revoke<", response.body.gsub(/\s+/, " ").scan(/<button[^>]*>[^<]*<\/button>/).join
    delete developers_authorized_app_path(@app)
    assert_not theirs.reload.revoked?
  end

  test "only public-API apps can be revoked here" do
    first_party = Doorkeeper::Application.create!(name: "TradingPost", redirect_uri: "https://example.com/cb")
    delete developers_authorized_app_path(first_party)
    assert_response :not_found
  end
end
