module Oauth
  # Verifies an OAuth access token presented to a protected resource (the MCP
  # server or the REST API), as MCP 2026-07-28 "Token Handling" and OAuth 2.1
  # §5.2 require: it must exist, be live, belong to an enabled client, and
  # have been issued for this resource (RFC 8707 audience). Tokens issued to
  # first-party apps (no resource) are never accepted here.
  #
  #   result = Oauth::VerifyToken.call(raw, resource: "https://data.buildcanada.com/mcp", scopes: ["read:public"])
  #   result.ok?     # => true
  #   result.caller  # => Keys::Caller (kind :oauth)
  #   result.error   # => nil, or :invalid_token, :token_expired, :token_revoked,
  #                  #    :wrong_audience, :suspended, :insufficient_scope
  #
  # Callers normally go through Keys::Authenticate, which picks this or
  # Keys::Verify from the token's format.
  class VerifyToken
    Result = Data.define(:caller, :error, :missing_scopes) do
      def ok? = error.nil?
    end

    MAX_LENGTH = 512

    def self.call(raw, **) = new(raw, **).call

    def initialize(raw, resource:, scopes: [], now: Time.current)
      @raw = raw.to_s.strip
      @resource = resource
      @scopes = Array(scopes).map(&:to_s)
      @now = now
    end

    def call
      return failure(:invalid_token) if @raw.empty? || @raw.length > MAX_LENGTH

      token = Doorkeeper::AccessToken.by_token(@raw)
      return failure(:invalid_token) unless token
      return failure(:token_revoked) if token.revoked?
      return failure(:token_expired) if token.expired?
      # Audience: a token for another resource, or a first-party token with
      # none, is refused (MCP "Access Token Privilege Restriction").
      return failure(:wrong_audience) unless token.resource.present? && ActiveSupport::SecurityUtils.secure_compare(token.resource, @resource)

      application = token.application
      return failure(:invalid_token) if application.nil? || application.disabled? || !application.public_api?

      account = token.account
      user = User.find_by(id: token.resource_owner_id)
      # The user must still belong to the account the token bills.
      return failure(:invalid_token) unless account && user && account.memberships.exists?(user_id: user.id)
      return failure(:suspended) if account.suspended?

      caller = Keys::Caller.for_oauth(token, account:, user:)
      missing = @scopes.reject { |scope| caller.scope?(scope) }
      return Result.new(caller:, error: :insufficient_scope, missing_scopes: missing) if missing.any?

      Result.new(caller:, error: nil, missing_scopes: [])
    end

    private

    def failure(error) = Result.new(caller: nil, error:, missing_scopes: [])
  end
end
