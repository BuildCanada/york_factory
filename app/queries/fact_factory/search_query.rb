module FactFactory
  # GET /v1/search (docs/public-interface-design.md §3.7): identifiers first,
  # then names whose match key equals the query's (entity_names, a derived
  # table versioned by revision), then (mode=fuzzy, when FuzzyNames has a
  # backend) approximate name candidates. Each hit says how it matched. Best
  # first: identifier, exact, then fuzzy by score; ties by entity ID.
  class SearchQuery
    RANKS = { "identifier" => 1, "exact" => 2, "fuzzy" => 3 }.freeze
    T_IDENTIFIERS = FactFactoryRecord.table("entity_identifiers")
    T_NAMES = FactFactoryRecord.table("entity_names")
    T_ENTITIES = FactFactoryRecord.table("entities")

    # `score_key` is the score exactly as the database compares it, for cursors.
    Hit = Data.define(:entity_id, :kind, :score, :score_key, :matched_on, :rank)

    def initialize(revision:, fuzzy: FuzzyNames.adapter)
      @revision = revision
      @fuzzy = fuzzy
      @entities = EntityQuery.new(revision:)
    end

    # A query with fewer than 2 letters or digits is too broad (DECISIONS 27).
    def self.too_broad?(q) = q.to_s.scan(/[\p{L}\p{N}]/).size < 2

    # True when mode=fuzzy was asked for and answered like exact.
    def fuzzy_unavailable?(mode) = mode == "fuzzy" && !@fuzzy.available?

    def page(q:, mode:, entity_class: nil, jurisdiction: nil, limit:, after: nil)
      values = { n: @revision, ident: identifier_value(q), key: Names.match_key(q), normalized: Names.normalize(q) }
      filters = [ @entities.current("e") ]
      if entity_class
        filters << "e.entity_class = :entity_class"
        values[:entity_class] = entity_class
      end
      if jurisdiction
        filters << "e.jurisdiction = :jurisdiction"
        values[:jurisdiction] = jurisdiction
      end
      arms = [ identifier_arm ]
      arms << exact_arm if values[:key]
      fuzzy = mode == "fuzzy" && values[:normalized] && @fuzzy.available? && @fuzzy.arm(current: @entities.current("n"))
      arms << fuzzy if fuzzy
      page_filter = "TRUE"
      if after
        page_filter = "(h.rank, -h.score, h.entity_id) > (:a_rank, -CAST(:a_score AS double precision), :a_id)"
        values.merge!(a_rank: after[0], a_score: after[1], a_id: after[2])
      end
      sql = <<~SQL
        WITH hits AS (#{arms.join(' UNION ALL ')}),
        best AS (
          SELECT DISTINCT ON (h.entity_id) h.* FROM hits h
          JOIN #{T_ENTITIES} e ON e.entity_id = h.entity_id AND #{filters.join(' AND ')}
          ORDER BY h.entity_id, h.rank, h.score DESC, h.matched_on
        )
        SELECT h.* FROM best h WHERE #{page_filter}
        ORDER BY h.rank, h.score DESC, h.entity_id
        LIMIT :limit
      SQL
      rows = Entity.connection.select_all(Entity.sanitize_sql_array([ sql, values.merge(limit: limit + 1) ]))
      rows.map do |r|
        Hit.new(entity_id: r["entity_id"], kind: r["kind"], score: r["score"].to_f.clamp(0, 1).round(6), score_key: r["score"].to_s,
          matched_on: r["matched_on"], rank: r["rank"].to_i)
      end
    end

    def entities(hits) = @entities.refs(hits.map(&:entity_id))

    private

    # An identifier as issuers write it: without spaces, and a 15-character
    # business number (program account) cut to its BN9.
    def identifier_value(q)
      value = q.to_s.gsub(/\s/, "")
      value.match?(/\A\d{9}[A-Z]{2}\d{4}\z/i) ? value[0, 9] : value
    end

    # entity_identifiers has an index on value alone.
    def identifier_arm
      <<~SQL
        SELECT i.entity_id, 'identifier' AS kind, 1.0::double precision AS score, 'identifier:' || i.namespace AS matched_on, 1 AS rank
        FROM #{T_IDENTIFIERS} i
        WHERE i.value = :ident AND #{@entities.current('i')}
      SQL
    end

    def exact_arm
      <<~SQL
        SELECT n.entity_id, 'exact', 1.0::double precision,
          CASE n.kind WHEN 'alias' THEN 'alias:' || n.name ELSE n.kind END, 2
        FROM #{T_NAMES} n
        WHERE n.match_key = :key AND #{@entities.current('n')}
      SQL
    end
  end
end
