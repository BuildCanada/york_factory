module Keys
  # Who is calling the public API: a verified key, or an anonymous caller
  # with read:public only (docs/public-interface-design.md D11). WS-D
  # controllers and WS-G MCP tools read scopes, plan and limits from here.
  Caller = Data.define(:api_key, :account, :scopes, :plan) do
    def self.anonymous = new(api_key: nil, account: nil, scopes: ApiKey::ANONYMOUS_SCOPES, plan: Plan.fetch("anonymous"))

    def self.for(api_key) = new(api_key:, account: api_key.account, scopes: api_key.scopes, plan: api_key.account.plan_definition)

    def anonymous? = api_key.nil?

    def scope?(scope) = scopes.include?(scope.to_s)

    def user = api_key&.user

    def inspect = "#<Keys::Caller key=#{api_key&.id.inspect} account=#{account&.id.inspect} scopes=#{scopes.inspect}>"
    alias_method :to_s, :inspect
  end
end
