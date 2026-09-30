module Keys
  # One entry point for every credential the public API and the MCP server
  # accept (docs/public-interface-design.md §4): an API key (bc_live_…,
  # bc_stg_…, or a legacy yfu_… key) goes to Keys::Verify; anything else is
  # treated as an OAuth access token and goes to Oauth::VerifyToken, which
  # checks that it was issued for `resource`.
  #
  #   result = Keys::Authenticate.call(raw, resource: Oauth::Settings.resource(:mcp, request),
  #                                    scopes: ["read:public"], ip: request.remote_ip, origin: request.origin)
  #   result.ok?            # => true
  #   result.caller         # => Keys::Caller, for keys and tokens alike
  #   result.error          # => nil, or a Keys::Verify / Oauth::VerifyToken error
  #   result.missing_scopes # => the scopes the caller lacks, on :insufficient_scope
  class Authenticate
    Result = Data.define(:caller, :error, :missing_scopes) do
      def ok? = error.nil?

      def oauth? = caller&.oauth? || false
    end

    def self.call(raw, **) = new(raw, **).call

    def self.api_key_format?(raw)
      raw.start_with?(ApiKey::Token::LEGACY_PREFIX) || ApiKey::Token::PREFIXES.any? { |prefix| raw.start_with?(prefix) }
    end

    def initialize(raw, resource:, scopes: [], ip: nil, origin: nil)
      @raw = raw.to_s.strip
      @resource = resource
      @scopes = Array(scopes).map(&:to_s)
      @ip = ip
      @origin = origin
    end

    def call
      return Result.new(caller: nil, error: :missing, missing_scopes: []) if @raw.empty?

      self.class.api_key_format?(@raw) ? verify_key : verify_token
    end

    private

    def verify_key
      result = Keys::Verify.call(@raw, scopes: @scopes, ip: @ip, origin: @origin)
      if result.error == :insufficient_scope
        caller = Keys::Caller.for(result.api_key)
        return Result.new(caller:, error: :insufficient_scope, missing_scopes: @scopes.reject { |scope| caller.scope?(scope) })
      end

      Result.new(caller: result.caller, error: result.error, missing_scopes: [])
    end

    def verify_token
      result = Oauth::VerifyToken.call(@raw, resource: @resource, scopes: @scopes)
      Result.new(caller: result.caller, error: result.error, missing_scopes: result.missing_scopes)
    end
  end
end
