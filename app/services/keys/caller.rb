module Keys
  # Who is calling the public API or the MCP server: the one principal for an
  # API key, an OAuth access token, or an anonymous caller with read:public
  # only (docs/public-interface-design.md D11). WS-D controllers and WS-G MCP
  # tools read scopes, account, plan and limits from here, whichever way the
  # caller authenticated. Build one with Keys::Authenticate.
  #
  #   caller.kind         # => :api_key, :oauth or :anonymous
  #   caller.account      # => the Account billed for usage (nil when anonymous)
  #   caller.user         # => the key's owner, or the user who authorized the OAuth client
  #   caller.scope?("read:persons")
  Caller = Data.define(:api_key, :oauth_token, :account, :user, :scopes, :plan) do
    def self.anonymous
      new(api_key: nil, oauth_token: nil, account: nil, user: nil, scopes: ApiKey::ANONYMOUS_SCOPES, plan: Plan.fetch("anonymous"))
    end

    def self.for(api_key)
      new(api_key:, oauth_token: nil, account: api_key.account, user: api_key.user, scopes: api_key.scopes, plan: api_key.account.plan_definition)
    end

    # An OAuth token's scopes are what the user consented to, narrowed to what
    # the account may still hold now (read:persons needs the data terms and a
    # plan that includes people data).
    def self.for_oauth(token, account:, user:)
      policy = Keys::Policy.new(account, user)
      scopes = token.scopes.to_a.map(&:to_s) & Oauth::Settings::SCOPES
      scopes -= [ "read:persons" ] unless policy.grantable?("read:persons")
      new(api_key: nil, oauth_token: token, account:, user:, scopes: scopes.sort, plan: account.plan_definition)
    end

    def kind
      if api_key then :api_key
      elsif oauth_token then :oauth
      else :anonymous
      end
    end

    def anonymous? = kind == :anonymous

    def oauth? = kind == :oauth

    def oauth_application = oauth_token&.application

    def scope?(scope) = scopes.include?(scope.to_s)

    def inspect = "#<Keys::Caller kind=#{kind} key=#{api_key&.id.inspect} token=#{oauth_token&.id.inspect} account=#{account&.id.inspect} scopes=#{scopes.inspect}>"
    alias_method :to_s, :inspect
  end
end
