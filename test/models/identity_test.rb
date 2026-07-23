require "test_helper"

class IdentityTest < ActiveSupport::TestCase
  def build_identity(**attrs)
    users(:member).identities.create!(
      { provider: "linkedin", uid: "li-x", access_token: "old", refresh_token: "ref" }.merge(attrs)
    )
  end

  # Temporarily replaces a class method with a stub returning `value`.
  def stubbing(klass, method, value)
    original = klass.method(method)
    klass.define_singleton_method(method) { |*_args| value }
    yield
  ensure
    klass.singleton_class.send(:define_method, method, original)
  end

  def stubbing_post_form(response, &)
    stubbing(Net::HTTP, :post_form, response, &)
  end

  test "access_token and refresh_token are encrypted at rest" do
    identity = build_identity(uid: "li-enc", access_token: "super-secret")
    ciphertext = Identity.connection.select_value(
      "SELECT access_token FROM identities WHERE id = #{identity.id}"
    )
    refute_equal "super-secret", ciphertext
    assert_equal "super-secret", identity.reload.access_token
  end

  test "token_expired? reflects token_expires_at" do
    assert build_identity(uid: "li-exp", token_expires_at: 1.hour.ago).token_expired?
    refute build_identity(uid: "li-fut", token_expires_at: 1.hour.from_now).token_expired?
    refute build_identity(uid: "li-nil", token_expires_at: nil).token_expired?
  end

  test "fresh_access_token returns the token without refreshing when still valid" do
    identity = build_identity(uid: "li-valid", token_expires_at: 1.hour.from_now, access_token: "valid-tok")
    # token_expired? is false, so refresh! (and any HTTP) is never reached.
    assert_equal "valid-tok", identity.fresh_access_token
  end

  test "refresh! exchanges the refresh token and persists the new tokens" do
    identity = build_identity(uid: "li-ref", token_expires_at: 1.hour.ago,
      access_token: "old-tok", refresh_token: "ref-1")

    response = Net::HTTPOK.new("1.1", "200", "OK")
    response.instance_variable_set(:@read, true)
    response.instance_variable_set(:@body,
      { access_token: "new-tok", refresh_token: "ref-2", expires_in: 3600 }.to_json)

    # Stub client creds so the test doesn't depend on decryptable credentials (CI has none).
    stubbing(Identity, :client_credentials, [ "client-id", "client-secret" ]) do
      stubbing_post_form(response) do
        assert identity.refresh!
      end
    end

    identity.reload
    assert_equal "new-tok", identity.access_token
    assert_equal "ref-2", identity.refresh_token
    assert identity.token_expires_at.future?
  end

  test "refresh! is a no-op without a refresh token" do
    identity = build_identity(uid: "li-noref", refresh_token: nil, token_expires_at: 1.hour.ago)
    # Returns early (before any HTTP) when there's no refresh token.
    refute identity.refresh!
  end
end
