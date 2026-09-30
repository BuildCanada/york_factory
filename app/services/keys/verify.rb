module Keys
  # Verifies a presented key (docs/public-interface-design.md §4.3). Shared by
  # the CMS routes (ApiKey.authenticate), the public API
  # (PublicApiAuthentication) and, later, the MCP server:
  #
  #   result = Keys::Verify.call(raw, scopes: ["read:public"], ip: request.remote_ip, origin: request.origin)
  #   result.ok?     # => true
  #   result.caller  # => Keys::Caller
  #   result.error   # => nil, or :missing, :malformed, :unknown, :revoked, :expired,
  #                  #    :suspended, :ip_not_allowed, :origin_not_allowed, :insufficient_scope
  #
  # A key is found by its HMAC digest (a unique index), and the stored digest
  # is compared in constant time. The format and checksum are checked first,
  # so a mistyped key costs no query. last_used_at is written at most once a
  # minute per key.
  class Verify
    Result = Data.define(:api_key, :error, :required_scope) do
      def ok? = error.nil?

      def caller = ok? ? Keys::Caller.for(api_key) : nil

      def inspect = "#<Keys::Verify::Result api_key=#{api_key&.id.inspect} error=#{error.inspect}>"
      alias_method :to_s, :inspect
    end

    def self.call(raw, **) = new(raw, **).call

    def initialize(raw, scopes: [], ip: nil, origin: nil, now: Time.current)
      @raw = raw.to_s.strip
      @scopes = Array(scopes).map(&:to_s)
      @ip = ip
      @origin = origin
      @now = now
    end

    def call
      return failure(:missing) if @raw.empty?

      api_key = find_key
      return failure(:malformed) if api_key == :malformed
      return failure(:unknown) unless api_key

      status = api_key.status(@now)
      return failure(status.to_sym, api_key) unless api_key.usable?(@now)
      return failure(:ip_not_allowed, api_key) unless api_key.ip_allowed?(@ip)
      return failure(:origin_not_allowed, api_key) unless api_key.origin_allowed?(@origin)

      missing = @scopes.find { |scope| !api_key.scope?(scope) }
      return Result.new(api_key:, error: :insufficient_scope, required_scope: missing) if missing

      api_key.record_use!(ip: @ip, at: @now)
      Result.new(api_key:, error: nil, required_scope: nil)
    end

    private

    def find_key
      if ApiKey::Token.legacy?(@raw)
        find_legacy_key
      elsif ApiKey::Token.well_formed?(@raw)
        lookup(ApiKey::Token.digest(@raw))
      else
        :malformed
      end
    end

    def lookup(digest)
      api_key = ApiKey.includes(:account, :user).find_by(token_digest: digest)
      api_key if api_key && ActiveSupport::SecurityUtils.secure_compare(api_key.token_digest, digest)
    end

    # yfu_ keys: the pepper digest once migrated, else the secret_key_base
    # digest, which is then replaced by the pepper digest.
    def find_legacy_key
      pepper_digest = ApiKey::Token.digest(@raw)
      lookup(pepper_digest) || lookup(ApiKey::Token.legacy_digest(@raw))&.tap do |api_key|
        ApiKey.where(id: api_key.id).update_all(token_digest: pepper_digest)
        api_key.token_digest = pepper_digest
        api_key.clear_attribute_changes([ :token_digest ])
      end
    end

    def failure(error, api_key = nil) = Result.new(api_key:, error:, required_scope: nil)
  end
end
