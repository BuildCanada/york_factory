module ApiKeyTestHelper
  def system_context = AuditEvent::Context.system

  def user_context(user) = AuditEvent::Context.new(actor: user, actor_kind: "user", ip: "203.0.113.9", user_agent: "test")

  def issue_key(user: users(:member), name: "test key #{SecureRandom.hex(3)}", scopes: ApiKey::DEFAULT_SCOPES, issuer: KeyIssuers::LocalIssuer.new, **options)
    result = Keys::Issue.call(account: Account.personal_for!(user), user:, name:, scopes:, issuer:, context: user_context(user), **options)
    assert result.ok?, "expected the key to be issued: #{result.api_key.errors.full_messages.to_sentence}"
    result
  end
end

ActiveSupport::TestCase.include(ApiKeyTestHelper)
