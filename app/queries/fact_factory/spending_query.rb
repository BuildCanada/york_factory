module FactFactory
  # Spending rows, their parties and entity summaries as of one release
  # (docs/public-interface-design.md §3.4). Shared by REST and MCP.
  #
  # A row is api.spending_records; its parties are the api.spending_parties
  # with the same (asset_key, acquisition, spending_row_id = id). An
  # occurrence is linked when entity_id is set, proposed when reason is
  # `proposed` (the proposed entity is candidates[0]), otherwise unlinked.
  class SpendingQuery
    # Party fields per role. `recipient` on /spending covers every
    # recipient-side field (DECISIONS 21; vendor_name is a contract's
    # recipient). An entity's own rows and summary use fact-factory's summary
    # roles (serve/read_model.SUMMARY_SQL), where research_org is its own role.
    FIELDS = {
      "payer" => %w[payer],
      "recipient" => %w[recipient recipients research_org principal_investigator vendor_name]
    }.freeze
    ENTITY_FIELDS = {
      "payer" => %w[payer],
      "recipient" => %w[recipient recipients principal_investigator vendor_name]
    }.freeze
    # The fields whose party_kind decides whether a row's postal code is shown
    # whole (fact-factory serve/allowlist.RECIPIENT_FIELDS).
    POSTAL_FIELDS = %w[recipient vendor_name].freeze
    EXCLUDED_REASONS = %w[excluded_individual excluded_aggregate excluded_unknown].freeze
    # Counterparty summaries are computed live; past this many linked rows the
    # query is refused (422 query_too_broad) rather than risk the timeout.
    COUNTERPARTY_ROW_LIMIT = 50_000

    # The text `q` searches: title, description, program and the party names
    # as published. One expression, so WS-B can index exactly it:
    #   CREATE INDEX ... ON api.spending_records USING gin (to_tsvector('simple', <TEXT>))
    TEXT = "coalesce(r.title, '') || ' ' || coalesce(r.description, '') || ' ' || coalesce(r.program, '') || ' ' || " \
      "coalesce(r.payer, '') || ' ' || coalesce(r.recipient, '') || ' ' || coalesce(r.research_org, '') || ' ' || " \
      "coalesce(r.principal_investigator, '') || ' ' || coalesce(r.recipients::text, '')".freeze

    SORTS = {
      "id" => [ nil, nil ],
      "amount" => [ "r.amount", "ASC" ],
      "-amount" => [ "r.amount", "DESC" ],
      "date" => [ "r.date", "ASC" ],
      "-date" => [ "r.date", "DESC" ]
    }.freeze

    attr_reader :release

    def initialize(release:)
      @release = release
    end

    def current(table_alias) = FactFactoryRecord.in_release(table_alias)

    # A page of rows. `filters` are the parsed parameters of listSpending or
    # listEntitySpending; `entity` scopes to one entity's rows in `role`.
    def page(filters:, sort:, limit:, after: nil, entity: nil, role: "recipient", include_proposed: false)
      where, values = conditions(filters, entity:, role:, include_proposed:)
      column, direction = SORTS.fetch(sort)
      where << keyset(column, direction, after, values) if after
      order = column ? "#{column} #{direction} NULLS LAST, r.spending_key" : "r.spending_key"
      sql = "SELECT r.*, r.id AS source_row_id FROM api.spending_records r WHERE #{where.join(' AND ')} ORDER BY #{order} LIMIT :limit"
      SpendingRecord.find_by_sql([ sql, values.merge(n: release, limit: limit + 1) ])
    end

    def count(filters:, entity: nil, role: "recipient", include_proposed: false)
      where, values = conditions(filters, entity:, role:, include_proposed:)
      select_value("SELECT count(*) FROM api.spending_records r WHERE #{where.join(' AND ')}", values).to_i
    end

    def find(spending_key)
      SpendingRecord.find_by_sql([
        "SELECT r.*, r.id AS source_row_id FROM api.spending_records r WHERE r.spending_key = :key AND #{current('r')} LIMIT 1",
        { key: spending_key, n: release }
      ]).first
    end

    # {[asset_key, acquisition, id] => [SpendingParty]} for the rows, in
    # (field, position) order.
    def parties(records)
      return {} if records.empty?

      tuples = records.map { |r| [ r.asset_key, r.acquisition, r.source_row_id ] }.uniq
      list = tuples.map { |t| "(#{t.map { |v| SpendingParty.connection.quote(v) }.join(', ')})" }.join(", ")
      sql = "SELECT p.* FROM api.spending_parties p WHERE (p.asset_key, p.acquisition, p.spending_row_id) IN (#{list}) " \
        "AND #{current('p')} ORDER BY p.field, p.position, p.occurrence_id"
      SpendingParty.find_by_sql([ sql, { n: release } ]).group_by { |p| [ p.asset_key, p.acquisition, p.spending_row_id ] }
    end

    # {spending_key => true/false}: whether each row is the highest-ranked
    # revision of its canonical_id, the only revision summaries count.
    def latest_revisions(records)
      return {} if records.empty?

      keys = records.map(&:spending_key)
      sql = "SELECT r.spending_key, NOT EXISTS (#{beaten_by('r')}) AS latest FROM api.spending_records r " \
        "WHERE r.spending_key IN (:keys) AND #{current('r')}"
      SpendingRecord.connection.select_rows(SpendingRecord.sanitize_sql_array([ sql, { keys:, n: release } ]))
        .to_h { |key, latest| [ key, ActiveModel::Type::Boolean.new.cast(latest) ] }
    end

    # An entity's summary from api.spending_summary, which fact-factory builds
    # per release under the fixed rules. Grouped by source (always), currency
    # (always) and fiscal_year when asked.
    def summary(entity_id, role:, by_year:, sources: nil, fiscal_year: nil)
      where = [ "s.release_id = :n", "s.entity_id = :entity", "s.role = :role" ]
      values = { n: release, entity: entity_id, role: }
      if sources
        where << "s.source_key IN (:sources)"
        values[:sources] = sources
      end
      unless fiscal_year.nil?
        where << "s.fiscal_year = :fiscal_year"
        values[:fiscal_year] = fiscal_year
      end
      year = by_year ? "s.fiscal_year" : "NULL::integer"
      sql = <<~SQL
        SELECT s.source_key, s.asset_key, #{year} AS fiscal_year, s.currency, s.measure,
          sum(s.record_count)::bigint AS records, sum(s.agreement_count)::bigint AS agreements,
          sum(s.amount) AS amount, sum(s.amount_missing_count)::bigint AS amount_missing,
          sum(s.aggregated_excluded)::bigint AS aggregated_excluded
        FROM api.spending_summary s WHERE #{where.join(' AND ')}
        GROUP BY s.source_key, s.asset_key, #{year}, s.currency, s.measure
        ORDER BY s.source_key, #{year} NULLS LAST, s.currency NULLS LAST
      SQL
      select_all(sql, values)
    end

    # The same summary split by counterparty, computed live under the same
    # rules as fact-factory's SUMMARY_SQL, for one entity.
    def counterparty_summary(entity_id, role:, by_year:, sources: nil, fiscal_year: nil)
      counter_role = role == "payer" ? "recipient" : "payer"
      values = { n: release, entity: entity_id, fields: ENTITY_FIELDS.fetch(role), counter_fields: ENTITY_FIELDS.fetch(counter_role) }
      linked_rows = select_value(<<~SQL, values).to_i
        SELECT count(DISTINCT (p.asset_key, p.spending_row_id)) FROM api.spending_parties p
        WHERE p.entity_id = :entity AND p.acquisition = 'live' AND p.field IN (:fields) AND #{current('p')}
      SQL
      return :too_broad if linked_rows > COUNTERPARTY_ROW_LIMIT

      filters = [ "TRUE" ]
      if sources
        filters << "r.source_key IN (:sources)"
        values[:sources] = sources
      end
      unless fiscal_year.nil?
        filters << "r.fiscal_year = :fiscal_year"
        values[:fiscal_year] = fiscal_year
      end
      year = by_year ? "r.fiscal_year" : "NULL::integer"
      sql = <<~SQL
        WITH mine AS (
          SELECT DISTINCT p.asset_key, p.spending_row_id AS id FROM api.spending_parties p
          WHERE p.entity_id = :entity AND p.acquisition = 'live' AND p.field IN (:fields) AND #{current('p')}
        ), live AS (
          SELECT DISTINCT ON (r.asset_key, r.id) r.asset_key, r.source_key, r.id, r.canonical_id, r.revision_rank,
            r.fiscal_year, r.currency, r.amount, coalesce(r.is_aggregated, false) AS is_aggregated
          FROM api.spending_records r
          WHERE r.acquisition = 'live' AND #{current('r')} AND (r.asset_key, r.canonical_id) IN (
            SELECT r2.asset_key, r2.canonical_id FROM api.spending_records r2 JOIN mine m ON m.asset_key = r2.asset_key AND m.id = r2.id
            WHERE r2.acquisition = 'live' AND #{current('r2')})
          ORDER BY r.asset_key, r.id, r.resource_id, r.source_occurrence
        ), ranked AS (
          SELECT live.*, (revision_rank IS NULL OR row_number() OVER (
            PARTITION BY asset_key, canonical_id ORDER BY revision_rank DESC NULLS LAST, id DESC) = 1) AS latest
          FROM live
        ), counter AS (
          SELECT DISTINCT p.asset_key, p.spending_row_id AS id, p.entity_id FROM api.spending_parties p
          JOIN mine m ON m.asset_key = p.asset_key AND m.id = p.spending_row_id
          WHERE p.acquisition = 'live' AND p.field IN (:counter_fields) AND p.entity_id IS NOT NULL AND #{current('p')}
        )
        SELECT r.source_key, r.asset_key, #{year} AS fiscal_year, r.currency, c.entity_id AS counterparty_id,
          count(*) FILTER (WHERE r.latest AND NOT r.is_aggregated) AS records,
          count(DISTINCT r.canonical_id) FILTER (WHERE r.latest AND NOT r.is_aggregated) AS agreements,
          sum(r.amount) FILTER (WHERE r.latest AND NOT r.is_aggregated) AS amount,
          count(*) FILTER (WHERE r.latest AND NOT r.is_aggregated AND r.amount IS NULL) AS amount_missing,
          count(*) FILTER (WHERE r.is_aggregated) AS aggregated_excluded
        FROM mine m
        JOIN ranked r ON r.asset_key = m.asset_key AND r.id = m.id
        LEFT JOIN counter c ON c.asset_key = r.asset_key AND c.id = r.id
        WHERE #{filters.join(' AND ')}
        GROUP BY r.source_key, r.asset_key, #{year}, r.currency, c.entity_id
        ORDER BY r.source_key, #{year} NULLS LAST, r.currency NULLS LAST, c.entity_id NULLS LAST
      SQL
      select_all(sql, values)
    end

    # Unlinked occurrences in `role` whose normalized name is one of the
    # entity's names or aliases in the release: candidates the reader may want
    # to check, never counted in the entity's spending.
    def unlinked(entity_id, role:, sources: nil, fiscal_year: nil, reasons: nil, limit:, after: nil)
      where, values = unlinked_conditions(entity_id, role:, sources:, fiscal_year:, reasons:)
      if after
        where << "p.row_id > :after"
        values[:after] = after[0]
      end
      sql = "SELECT p.* FROM api.spending_parties p WHERE #{where.join(' AND ')} ORDER BY p.row_id LIMIT :limit"
      SpendingParty.find_by_sql([ sql, values.merge(limit: limit + 1) ])
    end

    def unlinked_count(entity_id, role:, sources: nil, fiscal_year: nil)
      where, values = unlinked_conditions(entity_id, role:, sources:, fiscal_year:, reasons: nil)
      select_value("SELECT count(*) FROM api.spending_parties p WHERE #{where.join(' AND ')}", values).to_i
    end

    # {[asset_key, acquisition, id] => SpendingRecord}: the row each party is on.
    def records_for(parties)
      return {} if parties.empty?

      tuples = parties.map { |p| [ p.asset_key, p.acquisition, p.spending_row_id ] }.uniq
      list = tuples.map { |t| "(#{t.map { |v| SpendingRecord.connection.quote(v) }.join(', ')})" }.join(", ")
      sql = "SELECT DISTINCT ON (r.asset_key, r.acquisition, r.id) r.*, r.id AS source_row_id FROM api.spending_records r " \
        "WHERE (r.asset_key, r.acquisition, r.id) IN (#{list}) AND #{current('r')} " \
        "ORDER BY r.asset_key, r.acquisition, r.id, r.resource_id, r.source_occurrence"
      SpendingRecord.find_by_sql([ sql, { n: release } ]).index_by { |r| [ r.asset_key, r.acquisition, r.source_row_id ] }
    end

    private

    def conditions(filters, entity:, role:, include_proposed:)
      where = [ current("r") ]
      values = {}
      if filters["source"]
        where << "r.source_key IN (:sources)"
        values[:sources] = filters["source"]
      end
      if filters["fiscal_year"]
        where << "r.fiscal_year = :fiscal_year"
        values[:fiscal_year] = PublicApi::Format.fiscal_year_start(filters["fiscal_year"])
      end
      if filters["record_type"]
        where << "r.record_type = :record_type"
        values[:record_type] = filters["record_type"]
      end
      if filters["amount_min"]
        where << "r.amount >= CAST(:amount_min AS numeric)"
        values[:amount_min] = filters["amount_min"]
      end
      if filters["amount_max"]
        where << "r.amount <= CAST(:amount_max AS numeric)"
        values[:amount_max] = filters["amount_max"]
      end
      if filters["q"]
        where << "to_tsvector('simple', #{TEXT}) @@ plainto_tsquery('simple', :q)"
        values[:q] = filters["q"]
      end
      where << "NOT coalesce(r.is_aggregated, false)" if filters["include_aggregated"] == false
      where << "NOT EXISTS (#{beaten_by('r')})" if filters["latest_revision_only"]
      { "payer" => FIELDS["payer"], "recipient" => FIELDS["recipient"] }.each do |param, fields|
        next unless filters[param]

        where << linked_party(param, fields)
        values[:"#{param}_entity"] = PublicApi::Format.bare_id(filters[param], "Entity")
        values[:"#{param}_fields"] = fields
      end
      if entity
        proposed = include_proposed ? " OR (p.entity_id IS NULL AND p.reason = 'proposed' AND p.candidates->>0 = :entity)" : ""
        where << "EXISTS (SELECT 1 FROM api.spending_parties p WHERE p.asset_key = r.asset_key AND p.acquisition = r.acquisition " \
          "AND p.spending_row_id = r.id AND p.field IN (:entity_fields) AND #{current('p')} AND (p.entity_id = :entity#{proposed}))"
        values[:entity] = entity
        values[:entity_fields] = ENTITY_FIELDS.fetch(role)
      end
      [ where, values ]
    end

    def linked_party(param, _fields)
      "EXISTS (SELECT 1 FROM api.spending_parties p WHERE p.entity_id = :#{param}_entity AND p.field IN (:#{param}_fields) " \
        "AND p.asset_key = r.asset_key AND p.acquisition = r.acquisition AND p.spending_row_id = r.id AND #{current('p')})"
    end

    # Rows that outrank `r` within its (asset_key, acquisition, canonical_id):
    # a higher revision_rank, or the same rank and a higher id (SUMMARY_SQL's
    # ORDER BY revision_rank DESC NULLS LAST, id DESC), or the same source
    # record captured again in an earlier resource (its DISTINCT ON).
    def beaten_by(table_alias)
      r = table_alias
      "SELECT 1 FROM api.spending_records b WHERE b.asset_key = #{r}.asset_key AND b.acquisition = #{r}.acquisition " \
        "AND b.canonical_id = #{r}.canonical_id AND #{current('b')} AND (" \
        "(#{r}.revision_rank IS NOT NULL AND (b.revision_rank > #{r}.revision_rank OR (b.revision_rank = #{r}.revision_rank AND b.id > #{r}.id))) " \
        "OR (b.id = #{r}.id AND (b.resource_id, b.source_occurrence) < (#{r}.resource_id, #{r}.source_occurrence)))"
    end

    # Keyset condition after the cursor's (sort value, spending_key), blanks
    # sorting last in both directions.
    def keyset(column, direction, after, values)
      values[:after_key] = after.last
      return "r.spending_key > :after_key" unless column

      if after.first.nil?
        "(#{column} IS NULL AND r.spending_key > :after_key)"
      else
        values[:after_value] = after.first
        cast = column == "r.amount" ? "numeric" : "date"
        op = direction == "ASC" ? ">" : "<"
        "(#{column} #{op} CAST(:after_value AS #{cast}) OR (#{column} = CAST(:after_value AS #{cast}) AND r.spending_key > :after_key) OR #{column} IS NULL)"
      end
    end

    def unlinked_conditions(entity_id, role:, sources:, fiscal_year:, reasons:)
      where = [
        current("p"), "p.entity_id IS NULL", "p.field IN (:fields)",
        "coalesce(p.reason, '') NOT IN (:excluded)", "p.party_kind <> 'individual'",
        "p.normalized_name IN (SELECT n.normalized_name FROM api.entity_names n WHERE n.entity_id = :entity " \
        "AND n.normalized_name IS NOT NULL AND #{current('n')})"
      ]
      values = { n: release, entity: entity_id, fields: ENTITY_FIELDS.fetch(role), excluded: EXCLUDED_REASONS }
      if sources
        where << "p.asset_key IN (:assets)"
        values[:assets] = sources.filter_map { |s| PublicApi::Catalog.source(s)&.asset }.presence || [ "" ]
      end
      unless fiscal_year.nil?
        where << "p.fiscal_year = :fiscal_year"
        values[:fiscal_year] = fiscal_year
      end
      if reasons
        where << "p.reason IN (:reasons)"
        values[:reasons] = reasons
      end
      [ where, values ]
    end

    def select_value(sql, values) = SpendingRecord.connection.select_value(SpendingRecord.sanitize_sql_array([ sql, values.merge(n: release) ]))

    def select_all(sql, values) = SpendingRecord.connection.select_all(SpendingRecord.sanitize_sql_array([ sql, values.merge(n: release) ])).to_a
  end
end
