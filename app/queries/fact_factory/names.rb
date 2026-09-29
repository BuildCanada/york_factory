module FactFactory
  # fact-factory's name normalization (src/fact_factory/entities/names.py,
  # names-v2), ported so a query name is keyed the way api.entity_names keys
  # stored names. Keep the two in step: a change there is a new
  # NORMALIZATION_VERSION, and api.entity_names.normalization names the version
  # each row was built with.
  module Names
    NORMALIZATION_VERSION = "names-v2".freeze
    LEGAL_SUFFIXES = %w[
      incorporated incorporee inc corporation corp limited limitee ltd ltee llc llp lp ulc company co
      societe\ en\ commandite senc sencrl
    ].sort_by { |s| -s.length }.freeze
    LEADING_ARTICLES = %w[the].freeze

    module_function

    def normalize(name)
      return nil if name.nil?

      text = name.to_s.unicode_normalize(:nfkd).gsub(/\p{Mn}/, "").downcase(:fold)
      text = text.gsub(/[^\p{Word}[[:space:]]]/, " ").gsub(/[[:space:]]+/, " ").strip
      loop do
        suffix = LEGAL_SUFFIXES.find { |s| text.end_with?(" #{s}") }
        break unless suffix

        text = text[0...-(suffix.length + 1)].rstrip
      end
      text.presence
    end

    def match_key(name)
      text = normalize(name) or return nil
      first, rest = text.split(" ", 2)
      rest && LEADING_ARTICLES.include?(first) ? rest : text
    end
  end
end
