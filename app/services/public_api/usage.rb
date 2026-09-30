module PublicApi
  # Where GET /v1/me/usage reads usage buckets from: Usage::History (WS-I's
  # rollup tables, and Analytics Engine for minutes). Tests may swap it:
  #
  #   PublicApi::Usage.source = SomeSource.new
  #
  # A source answers #buckets(account:, granularity:, from:, to:, group_by:,
  # limit:, after:) with UsageBucket hashes oldest first, and
  # #caveats(locale:, granularity:, from:, to:) with Caveat objects.
  module Usage
    class << self
      attr_writer :source

      def source = @source ||= ::Usage::History.new
    end
  end
end
