module PublicApi
  # Where GET /v1/me/usage reads usage buckets from. WS-I (the metering rollup
  # into usage_daily, and the Analytics Engine client for today) plugs its
  # source in here:
  #
  #   PublicApi::Usage.source = Usage::Rollup.new
  #
  # A source answers #buckets(account:, granularity:, from:, to:, group_by:,
  # limit:, after:) with UsageBucket hashes oldest first, and #caveat(locale:).
  module Usage
    # Until the rollup exists: no history, and a caveat that says so.
    class Unrecorded
      def buckets(**) = []

      def caveat(locale:)
        detail = if locale == "fr"
          "L'historique d'utilisation n'est pas encore enregistré : le comptage (WS-I) n'est pas en service. Aucun intervalle n'est donc listé."
        else
          "Usage history is not recorded yet: the metering pipeline (WS-I) is not live, so no buckets are listed."
        end
        Catalog.caveat(:coverage_partial, locale:, detail:)
      end
    end

    class << self
      attr_writer :source

      def source = @source ||= Unrecorded.new
    end
  end
end
