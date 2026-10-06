module ApiKeyTestHelper
  def system_context = AuditEvent::Context.system

  def user_context(user) = AuditEvent::Context.new(actor: user, actor_kind: "user", ip: "203.0.113.9", user_agent: "test")

  def issue_key(user: users(:member), name: "test key #{SecureRandom.hex(3)}", scopes: ApiKey::DEFAULT_SCOPES, issuer: KeyIssuers::LocalIssuer.new, **options)
    result = Keys::Issue.call(account: Account.personal_for!(user), user:, name:, scopes:, issuer:, context: user_context(user), **options)
    assert result.ok?, "expected the key to be issued: #{result.api_key.errors.full_messages.to_sentence}"
    result
  end

  # The key with its last character changed, so the checksum fails. (Appending
  # a fixed character after chop leaves the key unchanged 1 time in 62.)
  def mistyped(raw) = raw.chop + (raw.end_with?("x") ? "y" : "x")
end

ActiveSupport::TestCase.include(ApiKeyTestHelper)
