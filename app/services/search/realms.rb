module Search
  module Realms
    REGISTRY = {
      "government_spending" => "Search::Realms::GovernmentSpending",
      "media" => "Search::Realms::Media",
      "kpi" => "Search::Realms::Kpi"
    }.freeze

    module_function

    def fetch(key)
      REGISTRY.fetch(key.to_s).constantize
    rescue KeyError
      raise ArgumentError, "unknown search realm: #{key.inspect}"
    end

    def key?(key)
      REGISTRY.key?(key.to_s)
    end

    def keys
      REGISTRY.keys
    end
  end
end
