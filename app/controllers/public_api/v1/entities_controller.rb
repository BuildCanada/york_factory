module PublicApi
  module V1
    # GET /v1/entities, /v1/entities/{id} and its identifiers, relationships
    # and lineage.
    class EntitiesController < BaseController
      include PublicApiEntityLookup

      operation :index, :listEntities
      operation :show, :getEntity
      operation :identifiers, :listEntityIdentifiers
      operation :relationships, :listEntityRelationships
      operation :lineage, :getEntityLineage

      EXPANDED_RELATIONSHIPS = 50

      def index
        check_fields!(EntitySerializer::ENTITY_FIELDS)
        filters = parameters.values.slice("class", "subtype", "jurisdiction", "status", "valid_on")
        sort = parameters["sort"]
        rows = entity_query.page(filters:, sort:, limit:, after:)
        page, next_cursor = paginate(rows) { |e| sort == "name" ? [ e.name, e.entity_id ] : [ e.entity_id ] }
        count = parameters["count"] == "exact" ? entity_query.count(filters:) : nil
        data = page.map { |e| project(EntitySerializer.entity(e, context)) }
        render_data({ data:, meta: list_meta(next_cursor:, count:), links: page_links(next_cursor) })
      end

      def show
        check_fields!(EntitySerializer::ENTITY_FIELDS)
        entity = load_entity! or return
        expand = Array(parameters["expand"])
        identifiers = entity_query.identifiers(entity.entity_id) if expand.include?("identifiers")
        relationships = expanded_relationships(entity) if expand.include?("relationships")
        data = project(EntitySerializer.entity(entity, context, identifiers:, relationships:))
        render_data({ data:, meta: meta, links: { self: self_link } })
      end

      def identifiers
        entity = load_entity! or return
        rows = entity_query.identifiers(entity.entity_id, namespace: parameters["namespace"], limit:, after:)
        page, next_cursor = paginate(rows) { |i| [ i.namespace, i.value, i.row_id ] }
        render_data({ data: page.map { |i| EntitySerializer.identifier(i, context) }, meta: list_meta(next_cursor:), links: page_links(next_cursor) })
      end

      def relationships
        entity = load_entity! or return
        rows = entity_query.relationships(entity.entity_id, predicates: parameters["predicate"], direction: parameters["direction"],
          valid_on: parameters["valid_on"], limit:, after:)
        page, next_cursor = paginate(rows) { |r| [ r.row_id, r.direction ] }
        render_data({ data: serialize_relationships(page), meta: list_meta(next_cursor:), links: page_links(next_cursor) })
      end

      def lineage
        entity = load_entity! or return
        direction = parameters["direction"]
        rows = entity_query.lineage(entity.entity_id, direction:, max_depth: parameters["max_depth"], limit:, after:)
        page, next_cursor = paginate(rows) { |r| [ r.depth.to_i, r.row_id ] }
        entities = entity_query.refs(page.map(&:step_entity_id))
        data = page.filter_map do |r|
          step = entities[r.step_entity_id] or next
          EntitySerializer.lineage_step(r, context, entity: step, direction:)
        end
        render_data({ data:, meta: list_meta(next_cursor:), links: page_links(next_cursor) })
      end

      private

      def expanded_relationships(entity)
        rows = entity_query.relationships(entity.entity_id, direction: "out", limit: EXPANDED_RELATIONSHIPS)
        serialize_relationships(rows.first(EXPANDED_RELATIONSHIPS))
      end

      def serialize_relationships(rows)
        objects = entity_query.refs(rows.map(&:object_id))
        rows.map { |r| EntitySerializer.relationship(r, context, object: objects[r.object_id], direction: r.direction) }
      end
    end
  end
end
