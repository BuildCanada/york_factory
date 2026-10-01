module FactFactory
  # Spending rows, their parties and entity summaries as of one registry
  # revision (docs/public-interface-design.md §3.4). Shared by REST and MCP.
  #
  # A row is spending_records, read through the publications revision N reads
  # (SpendingSlices). Its parties are the mention_occurrences current as of N
  # whose source_key is the row's slice label (the asset key, `@archive_import`
  # for archive copies) and spending_row_id its source id. An occurrence is
  # linked when entity_id is set, proposed when reason is `proposed` (the
  # proposed entity is candidates[0]), otherwise unlinked. Summaries are
  # fact-factory's derived tables (spending_summary, spending_counterparties),
  # versioned by revision like the registry.
  class SpendingQuery
    # Party fields per role. `recipient` on /spending covers every
    # recipient-side field (DECISIONS 21; vendor_name is a contract's
    # recipient). An entity's own rows and summary use fact-factory's summary
    # roles (derived.SUMMARY_SQL), where research_org is its own role.
    FIELDS = {
      "payer" => %w[payer],
      "recipient" => %w[recipient recipients research_org principal_investigator vendor_name]
    }.freeze
    ENTITY_FIELDS = {
      "payer" => %w[payer],
      "recipient" => %w[recipient recipients principal_investigator vendor_name]
    }.freeze
    # Occurrences never offered as candidates of an organization: individuals,
    # aggregates and unknown parties are kept out of organization matching
    # (fact-factory's person rule), so they are not "unlinked with this name".
    EXCLUDED_REASONS = %w[excluded_individual excluded_aggregate excluded_unknown].freeze

    T_RECORDS = FactFactoryRecord.table("spending_records")
    T_OCCURRENCES = FactFactoryRecord.table("mention_occurrences")
    T_NAMES = FactFactoryRecord.table("entity_names")
    T_SUMMARY = FactFactoryRecord.table("spending_summary")
    T_COUNTERPARTIES = FactFactoryRecord.table("spending_counterparties")

    # The text `q` searches: title, description, program and the single-valued
    # party names as published. One immutable expression, so a full-text index
    # can match it exactly (the recipients array is left out: array_to_string
    # is not immutable, and no index could match an expression using it):
    #   CREATE INDEX ... ON spending_records USING gin (to_tsvector('simple', <TEXT without r.>))
    TEXT = "coalesce(r.title, '') || ' ' || coalesce(r.description, '') || ' ' || coalesce(r.program, '') || ' ' || " \
      "coalesce(r.payer, '') || ' ' || coalesce(r.recipient, '') || ' ' || coalesce(r.research_org, '') || ' ' || " \
      "coalesce(r.principal_investigator, '')".freeze

    SORTS = {
      "id" => [ nil, nil ],
      "amount" => [ "r.amount", "ASC" ],
      "-amount" => [ "r.amount", "DESC" ],
      "date" => [ "r.date", "ASC" ],
      "-date" => [ "r.date", "DESC" ]
    }.freeze

    attr_reader :revision, :slices

    def initialize(revision:, slices: RevisionQuery.slices(revision))
      @revision = revision
      @slices = slices
    end

    def current(table_alias) = FactFactoryRecord.as_of(table_alias)

    # The slice label of a spending row (mention_occurrences.source_key).
    def self.label(source_key, acquisition)
      asset = PublicApi::Catalog.source(source_key)&.asset || source_key
      acquisition == "live" ? asset : "#{asset}@#{acquisition}"
    end

    def label_for(record) = self.class.label(record.source_key, record.acquisition)

    # The same label in SQL, for joining a row to its occurrences.
    def self.label_sql(table_alias = "r")
      cases = PublicApi::Catalog.sources.values.map { |s| "WHEN #{FactFactoryRecord.connection.quote(s.key)} THEN #{FactFactoryRecord.connection.quote(s.asset)}" }
      "(CASE #{table_alias}.source_key #{cases.join(' ')} ELSE #{table_alias}.source_key END || " \
        "CASE WHEN #{table_alias}.acquisition = 'live' THEN '' ELSE '@' || #{table_alias}.acquisition END)"
    end

    # A page of rows. `filters` are the parsed parameters of listSpending or
    # listEntitySpending; `entity` scopes to one entity's rows in `role`.
    def page(filters:, sort:, limit:, after: nil, entity: nil, role: "recipient", include_proposed: false)
      where, values = conditions(filters, entity:, role:, include_proposed:)
      column, direction = SORTS.fetch(sort)
      where << keyset(column, direction, after, values) if after
      order = column ? "#{column} #{direction} NULLS LAST, r.spending_key" : "r.spending_key"
      sql = "SELECT r.*, r.id AS source_row_id FROM #{T_RECORDS} r WHERE #{where.join(' AND ')} ORDER BY #{order} LIMIT :limit"
      SpendingRecord.find_by_sql([ sql, binds(values).merge(limit: limit + 1) ])
    end

    def count(filters:, entity: nil, role: "recipient", include_proposed: false)
      where, values = conditions(filters, entity:, role:, include_proposed:)
      select_value("SELECT count(*) FROM #{T_RECORDS} r WHERE #{where.join(' AND ')}", values).to_i
    end

    def find(spending_key)
      SpendingRecord.find_by_sql([
        "SELECT r.*, r.id AS source_row_id FROM #{T_RECORDS} r WHERE r.spending_key = :key AND r.publication_id IN (:pubs) LIMIT 1",
        binds(key: spending_key)
      ]).first
    end

    # {[label, source row id] => [Occurrence]} for the rows, in (field,
    # position) order.
    def parties(records)
      return {} if records.empty?

      tuples = records.map { |r| [ label_for(r), r.source_row_id ] }.uniq
      list = tuples.map { |t| "(#{t.map { |v| Occurrence.connection.quote(v) }.join(', ')})" }.join(", ")
      sql = "SELECT o.* FROM #{T_OCCURRENCES} o WHERE (o.source_key, o.spending_row_id) IN (#{list}) " \
        "AND #{current('o')} ORDER BY o.field, o.position, o.occurrence_id"
      Occurrence.find_by_sql([ sql, binds ]).group_by { |o| [ o.source_key, o.spending_row_id ] }
    end

    def parties_for(parties, record) = parties.fetch([ label_for(record), record.source_row_id ], [])

    # {spending_key => true/false}: whether each row is the latest revision
    # of its agreement (see #latest), what latest_revision_only keeps.
    def latest_revisions(records)
      return {} if records.empty?

      keys = records.map(&:spending_key)
      sql = "SELECT r.spending_key, #{latest('r')} AS latest FROM #{T_RECORDS} r " \
        "WHERE r.spending_key IN (:keys) AND r.publication_id IN (:pubs)"
      SpendingRecord.connection.select_rows(SpendingRecord.sanitize_sql_array([ sql, binds(keys:) ]))
        .to_h { |key, latest| [ key, ActiveModel::Type::Boolean.new.cast(latest) ] }
    end

    # An entity's summary as of the revision (spending_summary). Grouped by
    # source (always), currency (always) and fiscal_year when asked. Empty when
    # nothing is linked to the entity, as everywhere before any match rule is
    # active.
    def summary(entity_id, role:, by_year:, sources: nil, fiscal_year: nil)
      summary_rows(T_SUMMARY, entity_id, role:, by_year:, sources:, fiscal_year:)
    end

    # The same summary split by counterparty (spending_counterparties: the
    # other side's linked entity on each counted row; blank when none is linked).
    def counterparty_summary(entity_id, role:, by_year:, sources: nil, fiscal_year: nil)
      summary_rows(T_COUNTERPARTIES, entity_id, role:, by_year:, sources:, fiscal_year:, counterparty: true)
    end

    # Unlinked occurrences in `role` whose normalized name is one of the
    # entity's names or aliases as of the revision: candidates the reader may
    # want to check, never counted in the entity's spending.
    def unlinked(entity_id, role:, sources: nil, fiscal_year: nil, reasons: nil, limit:, after: nil)
      where, values = unlinked_conditions(entity_id, role:, sources:, fiscal_year:, reasons:)
      if after
        where << "o.row_id > :after"
        values[:after] = after[0]
      end
      sql = "SELECT o.* FROM #{T_OCCURRENCES} o WHERE #{where.join(' AND ')} ORDER BY o.row_id LIMIT :limit"
      Occurrence.find_by_sql([ sql, binds(values).merge(limit: limit + 1) ])
    end

    def unlinked_count(entity_id, role:, sources: nil, fiscal_year: nil)
      where, values = unlinked_conditions(entity_id, role:, sources:, fiscal_year:, reasons: nil)
      select_value("SELECT count(*) FROM #{T_OCCURRENCES} o WHERE #{where.join(' AND ')}", values).to_i
    end

    # {[label, source row id] => SpendingRecord}: the row each occurrence is on,
    # in the publications its slice reads (the first resource holding it, as
    # the summary counts it).
    def records_for(occurrences)
      wanted = occurrences.map { |o| [ o.source_key, o.spending_row_id ] }.uniq
      return {} if wanted.empty?

      ids = wanted.map(&:last).uniq
      sql = "SELECT r.*, r.id AS source_row_id FROM #{T_RECORDS} r WHERE r.id IN (:ids) AND r.publication_id IN (:pubs) " \
        "ORDER BY r.id, r.resource_id, r.source_occurrence"
      found = SpendingRecord.find_by_sql([ sql, binds(ids:) ]).group_by { |r| [ label_for(r), r.source_row_id ] }
      wanted.filter_map { |key| found[key]&.first&.then { |r| [ key, r ] } }.to_h
    end

    private

    def binds(values = {}) = values.merge(n: revision, pubs: slices.publication_ids.presence || [ 0 ])

    def summary_rows(table, entity_id, role:, by_year:, sources:, fiscal_year:, counterparty: false)
      where = [ current("s"), "s.entity_id = :entity", "s.role = :role" ]
      values = { entity: entity_id, role: }
      if sources
        where << "s.source_key IN (:sources)"
        values[:sources] = sources
      end
      unless fiscal_year.nil?
        where << "s.fiscal_year = :fiscal_year"
        values[:fiscal_year] = fiscal_year
      end
      year = by_year ? "s.fiscal_year" : "NULL::integer"
      party = counterparty ? ", s.counterparty_id" : ""
      sql = <<~SQL
        SELECT s.source_key, s.asset_key, #{year} AS fiscal_year, s.currency, s.measure#{party},
          sum(s.record_count)::bigint AS records, sum(s.agreement_count)::bigint AS agreements,
          sum(s.amount) AS amount, sum(s.amount_missing_count)::bigint AS amount_missing,
          sum(s.aggregated_excluded)::bigint AS aggregated_excluded
        FROM #{table} s WHERE #{where.join(' AND ')}
        GROUP BY s.source_key, s.asset_key, #{year}, s.currency, s.measure#{party}
        ORDER BY s.source_key, #{year} NULLS LAST, s.currency NULLS LAST#{counterparty ? ', s.counterparty_id NULLS LAST' : ''}
      SQL
      select_all(sql, values)
    end

    def conditions(filters, entity:, role:, include_proposed:)
      where = [ "r.publication_id IN (:pubs)" ]
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
      where << latest("r") if filters["latest_revision_only"]
      { "payer" => FIELDS["payer"], "recipient" => FIELDS["recipient"] }.each do |param, fields|
        next unless filters[param]

        where << "EXISTS (SELECT 1 FROM #{T_OCCURRENCES} o WHERE o.entity_id = :#{param}_entity AND o.field IN (:#{param}_fields) " \
          "AND o.source_key = #{self.class.label_sql} AND o.spending_row_id = r.id AND #{current('o')})"
        values[:"#{param}_entity"] = PublicApi::Format.bare_id(filters[param], "Entity")
        values[:"#{param}_fields"] = fields
      end
      if entity
        proposed = include_proposed ? " OR (o.entity_id IS NULL AND o.reason = 'proposed' AND CAST(o.candidates AS jsonb)->>0 = :entity)" : ""
        where << "EXISTS (SELECT 1 FROM #{T_OCCURRENCES} o WHERE o.source_key = #{self.class.label_sql} AND o.spending_row_id = r.id " \
          "AND o.field IN (:entity_fields) AND #{current('o')} AND (o.entity_id = :entity#{proposed}))"
        values[:entity] = entity
        values[:entity_fields] = ENTITY_FIELDS.fetch(role)
      end
      [ where, values ]
    end

    # Whether `r` is the latest revision of its agreement. Within its slice
    # (source and acquisition) it must not be outranked (#beaten_by, as
    # derived.SUMMARY_SQL ranks). Live data wins across slices (DECISIONS 38):
    # an archive_import row counts only when no live row the revision reads has
    # its canonical_id, so an agreement only the archive has still shows.
    def latest(table_alias)
      r = table_alias
      "(NOT EXISTS (#{beaten_by(r)}) AND (#{r}.acquisition = 'live' OR NOT EXISTS (" \
        "SELECT 1 FROM #{T_RECORDS} l WHERE l.canonical_id = #{r}.canonical_id AND l.source_key = #{r}.source_key " \
        "AND l.acquisition = 'live' AND l.publication_id IN (:pubs))))"
    end

    # Rows that outrank `r` in its slice and agreement: a higher revision_rank,
    # or the same rank and a higher id (ORDER BY revision_rank DESC NULLS LAST,
    # id DESC), or the same source record captured again in an earlier resource
    # (the summary's DISTINCT ON).
    def beaten_by(table_alias)
      r = table_alias
      rank = ->(t) { "CAST(#{t}.revision_rank_json AS jsonb)" }
      "SELECT 1 FROM #{T_RECORDS} b WHERE b.canonical_id = #{r}.canonical_id AND b.source_key = #{r}.source_key " \
        "AND b.acquisition = #{r}.acquisition AND b.publication_id IN (:pubs) AND (" \
        "(#{r}.revision_rank_json IS NOT NULL AND (#{rank.(:b)} > #{rank.(r)} OR (#{rank.(:b)} = #{rank.(r)} AND b.id > #{r}.id))) " \
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
        current("o"), "o.entity_id IS NULL", "o.field IN (:fields)",
        "coalesce(o.reason, '') NOT IN (:excluded)", "o.party_kind <> 'individual'",
        "o.normalized_name IN (SELECT n.normalized_name FROM #{T_NAMES} n WHERE n.entity_id = :entity " \
        "AND n.normalized_name IS NOT NULL AND #{current('n')})"
      ]
      values = { entity: entity_id, fields: ENTITY_FIELDS.fetch(role), excluded: EXCLUDED_REASONS }
      if sources
        labels = sources.filter_map { |s| PublicApi::Catalog.source(s)&.asset }.flat_map { |a| [ a, "#{a}@archive_import" ] }
        where << "o.source_key IN (:labels)"
        values[:labels] = labels.presence || [ "" ]
      end
      unless fiscal_year.nil?
        where << "o.fiscal_year = :fiscal_year"
        values[:fiscal_year] = fiscal_year
      end
      if reasons
        where << "o.reason IN (:reasons)"
        values[:reasons] = reasons
      end
      [ where, values ]
    end

    def select_value(sql, values) = SpendingRecord.connection.select_value(SpendingRecord.sanitize_sql_array([ sql, binds(values) ]))

    def select_all(sql, values) = SpendingRecord.connection.select_all(SpendingRecord.sanitize_sql_array([ sql, binds(values) ])).to_a
  end
end
