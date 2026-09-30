module FactFactory
  # GET /v1/search (docs/public-interface-design.md §3.7): identifiers first,
  # then names equal after normalization, then (mode=fuzzy) trigram
  # candidates. Each hit says how it matched. Best first: identifier, exact,
  # then fuzzy by similarity; ties by entity ID.
  class SearchQuery
    FUZZY_THRESHOLD = 0.3
    # Fuzzy candidates considered per query, before paging.
    FUZZY_CANDIDATES = 500
    RANKS = { "identifier" => 1, "exact" => 2, "fuzzy" => 3 }.freeze

    # `score_key` is the score exactly as the database compares it, for cursors.
    Hit = Data.define(:entity_id, :kind, :score, :score_key, :matched_on, :rank)

    def initialize(release:)
      @release = release
      @entities = EntityQuery.new(release:)
    end

    # A query with fewer than 2 letters or digits is too broad (DECISIONS 27).
    def self.too_broad?(q) = q.to_s.scan(/[\p{L}\p{N}]/).size < 2

    def page(q:, mode:, entity_class: nil, jurisdiction: nil, limit:, after: nil)
      values = {
        n: @release, ident: identifier_value(q), key: Names.match_key(q), normalized: Names.normalize(q),
        threshold: FUZZY_THRESHOLD, candidates: FUZZY_CANDIDATES
      }
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
      arms << fuzzy_arm(trigram_schema) if mode == "fuzzy" && values[:normalized] && trigram_schema
      page_filter = "TRUE"
      if after
        page_filter = "(h.rank, -h.score, h.entity_id) > (:a_rank, -CAST(:a_score AS double precision), :a_id)"
        values.merge!(a_rank: after[0], a_score: after[1], a_id: after[2])
      end
      sql = <<~SQL
        WITH hits AS (#{arms.join(' UNION ALL ')}),
        best AS (
          SELECT DISTINCT ON (h.entity_id) h.* FROM hits h
          JOIN api.entities e ON e.entity_id = h.entity_id AND #{filters.join(' AND ')}
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

    def identifier_arm
      <<~SQL
        SELECT i.entity_id, 'identifier' AS kind, 1.0::double precision AS score, 'identifier:' || i.namespace AS matched_on, 1 AS rank
        FROM api.identifiers i
        WHERE i.value = :ident AND i.namespace IN (#{namespaces_sql}) AND #{@entities.current('i')}
      SQL
    end

    def exact_arm
      <<~SQL
        SELECT n.entity_id, 'exact', 1.0::double precision,
          CASE n.kind WHEN 'alias' THEN 'alias:' || n.name ELSE n.kind END, 2
        FROM api.entity_names n
        WHERE n.match_key = :key AND #{@entities.current('n')}
      SQL
    end

    # pg_trgm's similarity and % operator, qualified by the schema the
    # extension is in: the api_reader role's search_path is only `api`.
    def fuzzy_arm(schema)
      similarity = "#{schema}.similarity(n.normalized_name, CAST(:normalized AS text))"
      <<~SQL
        SELECT * FROM (
          SELECT n.entity_id, 'fuzzy', #{similarity}::double precision,
            CASE n.kind WHEN 'alias' THEN 'alias:' || n.name ELSE n.kind END, 3
          FROM api.entity_names n
          WHERE n.normalized_name OPERATOR(#{schema}.%) CAST(:normalized AS text) AND #{@entities.current('n')}
          ORDER BY #{similarity} DESC
          LIMIT :candidates
        ) f
      SQL
    end

    # Identifier namespaces present in the release, so the lookup uses the
    # (namespace, value) index. Cached per release: releases are immutable.
    def namespaces_sql
      list = self.class.namespaces(@release)
      list.empty? ? "NULL" : list.map { |ns| Entity.connection.quote(ns) }.join(", ")
    end

    def self.namespaces(release)
      @namespaces ||= {}
      @namespaces[release] ||= Identifier.connection.select_values(
        Identifier.sanitize_sql_array([ "SELECT DISTINCT namespace FROM api.identifiers i WHERE #{FactFactoryRecord.in_release('i')}", { n: release } ])
      )
    end

    def self.reset! = @namespaces = nil

    # The schema pg_trgm is installed in, or nil (fuzzy search off, as in
    # fact-factory when the extension is unavailable).
    def trigram_schema
      self.class.trigram_schema
    end

    def self.trigram_schema
      return @trigram_schema if defined?(@trigram_schema)

      schema = Entity.connection.select_value("SELECT extnamespace::regnamespace::text FROM pg_extension WHERE extname = 'pg_trgm'")
      @trigram_schema = schema && Entity.connection.quote_table_name(schema)
    end
  end
end
