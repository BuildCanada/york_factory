module FactFactory
  # Fuzzy name search (mode=fuzzy on /v1/search) behind an adapter, so the
  # backend can change without touching the search query. fact-factory keeps no
  # trigram index: fuzzy name search will use PlanetScale's `tin` extension after
  # the database moves there (fact-factory RUNBOOK, "Derived tables"; SUCKS.md).
  # Until then there is no backend, and mode=fuzzy answers like exact, with the
  # fuzzy_unavailable caveat.
  #
  # An adapter answers #available? and #arm(current:), the SQL of one UNION arm
  # yielding (entity_id, kind 'fuzzy', score, matched_on, rank 3) for the bind
  # :normalized, over entity_names n as of :n.
  module FuzzyNames
    class Unavailable
      def available? = false

      def arm(current:) = nil
    end

    # TODO(PlanetScale): match entity_names.normalized_name with tin once
    # fact-factory's database moves to PlanetScale and an index exists. Until
    # then it reports unavailable, even where the extension happens to be
    # installed (york_factory's own database has it; fact-factory's has none).
    class Tin < Unavailable; end

    class << self
      attr_writer :adapter

      def adapter = @adapter ||= Unavailable.new
    end
  end
end
