module FactFactory
  # Entities, identifiers, relationships and lineage as of one release. Shared
  # by the REST controllers and the MCP server (WS-G), so the two can't drift.
  #
  # Person entities (entity_class person, phase 2) are served like any other
  # class, under read:public (decided 2026-09-29).
  class EntityQuery
    # The phase 1 predicates (the contract's Predicate enum). Person
    # predicates (director_of, has_significant_control_over) arrive with
    # phase 2's contract and are not served until the enum has them.
    PREDICATES = %w[governs located_within covers party_to administrative_part_of reports_to_minister owned_by controlled_by member_of succeeded_by].freeze

    attr_reader :release

    def initialize(release:)
      @release = release
    end

    def find(entity_id)
      Entity.find_by_sql([ "SELECT * FROM api.entities e WHERE e.entity_id = :id AND #{current('e')} LIMIT 1", binds(id: entity_id) ]).first
    end

    # {entity_id => Entity} for the ones current in the release.
    def refs(entity_ids)
      ids = entity_ids.compact.uniq
      return {} if ids.empty?

      Entity.find_by_sql([ "SELECT * FROM api.entities e WHERE e.entity_id IN (:ids) AND #{current('e')}", binds(ids:) ])
        .index_by(&:entity_id)
    end

    def page(filters:, sort:, limit:, after: nil)
      where, values = list_conditions(filters)
      order = sort == "name" ? "e.name, e.entity_id" : "e.entity_id"
      if after
        if sort == "name"
          where << "(e.name, e.entity_id) > (:after_name, :after_id)"
          values.merge!(after_name: after[0], after_id: after[1])
        else
          where << "e.entity_id > :after_id"
          values[:after_id] = after[0]
        end
      end
      sql = "SELECT e.* FROM api.entities e WHERE #{where.join(' AND ')} ORDER BY #{order} LIMIT :limit"
      Entity.find_by_sql([ sql, binds(**values, limit: limit + 1) ])
    end

    def count(filters:)
      where, values = list_conditions(filters)
      Entity.connection.select_value(Entity.sanitize_sql_array([ "SELECT count(*) FROM api.entities e WHERE #{where.join(' AND ')}", binds(**values) ])).to_i
    end

    def identifiers(entity_id, namespace: nil, limit: nil, after: nil)
      where = [ "i.entity_id = :id", current("i") ]
      values = { id: entity_id }
      if namespace
        where << "i.namespace = :namespace"
        values[:namespace] = namespace
      end
      if after
        where << "(i.namespace, i.value, i.row_id) > (:a_ns, :a_value, :a_row)"
        values.merge!(a_ns: after[0], a_value: after[1], a_row: after[2])
      end
      sql = "SELECT i.* FROM api.identifiers i WHERE #{where.join(' AND ')} ORDER BY i.namespace, i.value, i.row_id"
      sql += " LIMIT :limit" if limit
      Identifier.find_by_sql([ sql, binds(**values, limit: limit.to_i + 1) ])
    end

    # Holders of one identifier (GET /v1/identifiers/{namespace}/{value}).
    def holders(namespace, value)
      sql = <<~SQL
        SELECT i.* FROM api.identifiers i
        JOIN api.entities e ON e.entity_id = i.entity_id AND #{current('e')}
        WHERE i.namespace = :namespace AND i.value = :value AND #{current('i')}
        ORDER BY i.entity_id, i.row_id
      SQL
      Identifier.find_by_sql([ sql, binds(namespace:, value:) ])
    end

    # One page of an entity's relationships, each with its `direction`
    # relative to the entity.
    def relationships(entity_id, predicates: nil, direction: "both", valid_on: nil, limit:, after: nil)
      predicates = Array(predicates).presence || PREDICATES
      values = { id: entity_id, predicates: predicates & PREDICATES }
      return [] if values[:predicates].empty?

      sides = []
      sides << "SELECT r.*, 'out' AS direction FROM api.relationships r WHERE r.subject_id = :id AND r.predicate IN (:predicates) AND #{current('r')}" if direction.in?(%w[out both])
      sides << "SELECT r.*, 'in' AS direction FROM api.relationships r WHERE r.object_id = :id AND r.predicate IN (:predicates) AND #{current('r')}" if direction.in?(%w[in both])
      where = [ "TRUE" ]
      if valid_on
        where << valid_on_condition("s")
        values[:valid_on] = valid_on
      end
      if after
        where << "(s.row_id, s.direction) > (:a_row, :a_direction)"
        values.merge!(a_row: after[0], a_direction: after[1])
      end
      sql = "SELECT s.* FROM (#{sides.join(' UNION ALL ')}) s WHERE #{where.join(' AND ')} ORDER BY s.row_id, s.direction LIMIT :limit"
      Relationship.find_by_sql([ sql, binds(**values, limit: limit + 1) ])
    end

    # Predecessors or successors along succeeded_by, nearest first: one step
    # per relationship, at its shortest depth. "A succeeded_by B" makes A a
    # predecessor of B.
    def lineage(entity_id, direction:, max_depth:, limit:, after: nil)
      near, far = direction == "successors" ? %w[subject_id object_id] : %w[object_id subject_id]
      values = { id: entity_id, max_depth: }
      page = "TRUE"
      if after
        page = "(s.depth, s.row_id) > (:a_depth, :a_row)"
        values.merge!(a_depth: after[0], a_row: after[1])
      end
      sql = <<~SQL
        WITH RECURSIVE walk(entity_id, depth, row_id, path) AS (
          SELECT r.#{far}, 1, r.row_id, ARRAY[CAST(:id AS text), r.#{far}]
          FROM api.relationships r
          WHERE r.predicate = 'succeeded_by' AND r.#{near} = :id AND r.#{far} IS NOT NULL AND #{current('r')}
          UNION ALL
          SELECT r.#{far}, w.depth + 1, r.row_id, w.path || r.#{far}
          FROM walk w
          JOIN api.relationships r ON r.predicate = 'succeeded_by' AND r.#{near} = w.entity_id AND #{current('r')}
          WHERE w.depth < :max_depth AND r.#{far} IS NOT NULL AND NOT r.#{far} = ANY(w.path)
        ), steps AS (
          SELECT DISTINCT ON (w.row_id) w.row_id, w.depth, w.entity_id AS step_entity_id FROM walk w ORDER BY w.row_id, w.depth
        )
        SELECT s.* FROM (
          SELECT r.*, st.depth, st.step_entity_id FROM steps st JOIN api.relationships r ON r.row_id = st.row_id
        ) s
        WHERE #{page}
        ORDER BY s.depth, s.row_id
        LIMIT :limit
      SQL
      Relationship.find_by_sql([ sql, binds(**values, limit: limit + 1) ])
    end

    def current(table_alias) = FactFactoryRecord.in_release(table_alias)

    private

    def binds(**values) = values.merge(n: release)

    def list_conditions(filters)
      where = [ current("e") ]
      values = {}
      { "class" => "entity_class", "subtype" => "subtype", "jurisdiction" => "jurisdiction", "status" => "status" }.each do |param, column|
        next if filters[param].nil?

        where << "e.#{column} = :#{column}"
        values[column.to_sym] = filters[param]
      end
      if filters["valid_on"]
        where << valid_on_condition("e")
        values[:valid_on] = filters["valid_on"]
      end
      [ where, values ]
    end

    # valid_on (the ValidOn parameter) against partial dates: a year or month
    # start counts from its first day, and an end runs to its last day.
    def valid_on_condition(table_alias)
      from = "#{table_alias}.valid_from"
      to = "#{table_alias}.valid_to"
      "(#{from} IS NULL OR (CASE length(#{from}) WHEN 4 THEN #{from} || '-01-01' WHEN 7 THEN #{from} || '-01' ELSE #{from} END) <= :valid_on) " \
        "AND (#{to} IS NULL OR (CASE length(#{to}) WHEN 4 THEN #{to} || '-12-31' WHEN 7 THEN #{to} || '-31' ELSE #{to} END) > :valid_on)"
    end
  end
end
