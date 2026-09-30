module PublicApi
  module V1
    # Entity, EntityRef, Identifier, Relationship and LineageStep (the
    # contract's components/schemas).
    module EntitySerializer
      REGISTRY_LICENSE = "OGL-Canada-2.0".freeze
      ASSETS = { entity: "entities/entities", identifier: "entities/identifiers", relationship: "entities/relationships" }.freeze
      ENTITY_FIELDS = %w[id entity_class subtype name name_fr aliases anchor jurisdiction status redirected_to valid_from valid_to
                         attributes identifiers relationships links provenance cite].freeze

      module_function

      def entity(e, ctx, identifiers: nil, relationships: nil)
        base = "/v1/entities/#{e.entity_id}"
        data = {
          id: Format.entity_gid(e.entity_id),
          entity_class: e.entity_class,
          subtype: e.subtype,
          name: e.name,
          name_fr: e.name_fr,
          aliases: Array(e.aliases).map(&:to_s),
          anchor: e.anchor,
          jurisdiction: jurisdiction(e.jurisdiction),
          status: e.status.presence || "active",
          redirected_to: Format.entity_gid(e.redirected_to),
          valid_from: Format.partial_date(e.valid_from),
          valid_to: Format.partial_date(e.valid_to),
          attributes: json_object(e["attributes"])
        }
        data[:identifiers] = identifiers.map { |i| identifier(i, ctx) } if identifiers
        data[:relationships] = relationships if relationships
        data[:links] = {
          identifiers: ctx.pin("#{base}/identifiers"), relationships: ctx.pin("#{base}/relationships"),
          lineage: ctx.pin("#{base}/lineage"), spending: ctx.pin("#{base}/spending")
        }
        data[:provenance] = provenance(e, ASSETS[:entity])
        data[:cite] = cite(ctx, "gid://buildcanada/Entity/#{e.entity_id}", e.source)
        data
      end

      def ref(e)
        {
          id: Format.entity_gid(e.entity_id), name: e.name, entity_class: e.entity_class, subtype: e.subtype,
          jurisdiction: jurisdiction(e.jurisdiction), status: e.status.presence || "active"
        }
      end

      def identifier(i, _ctx)
        {
          namespace: i.namespace, value: i.value, verified: i.verified.to_i == 1, vintage: i.vintage,
          valid_from: Format.partial_date(i.valid_from), valid_to: Format.partial_date(i.valid_to),
          provenance: provenance(i, ASSETS[:identifier])
        }
      end

      # `object` is the object entity (an Entity or nil); `direction` is the
      # side of the requested entity.
      def relationship(r, ctx, object:, direction:)
        {
          id: r.row_id,
          subject_id: Format.entity_gid(r.subject_id),
          predicate: r.predicate,
          object_id: Format.entity_gid(r.object_id),
          object_ref: r.object_id ? nil : r.object_ref,
          object: object && ref(object),
          direction:,
          attributes: json_object(r["attributes"]),
          valid_from: Format.partial_date(r.valid_from),
          valid_to: Format.partial_date(r.valid_to),
          provenance: provenance(r, ASSETS[:relationship]),
          cite: cite(ctx, ctx.fr? ? "relation #{r.predicate} de gid://buildcanada/Entity/#{r.subject_id}" : "relationship #{r.predicate} of gid://buildcanada/Entity/#{r.subject_id}", r.source)
        }
      end

      def lineage_step(r, ctx, entity:, direction:)
        attributes = json_object(r["attributes"])
        {
          depth: r.depth.to_i,
          entity: ref(entity),
          event: attributes["event"]&.to_s,
          effective_date: Format.partial_date(attributes["effective_date"]),
          relationship: relationship(r, ctx, object: nil, direction: direction == "successors" ? "out" : "in")
            .merge(object: nil)
        }
      end

      # Provenance of a registry row version: the release that first published
      # it, when fact-factory recorded it, and the roster row it came from.
      def provenance(row, asset)
        source = record_source(row.source)
        {
          asset:, release: row.release_from, snapshot_id: nil, recorded_at: Format.timestamp(row.recorded_at),
          capture: nil, locator: source&.dig(:row_number) ? { row: source[:row_number] } : nil, source:,
          parser_version: nil, license: REGISTRY_LICENSE
        }
      end

      # RecordSource: `roster` for rows built from a roster capture; anything
      # else (resolution, creation, reviewed decisions) was made by entity
      # resolution.
      def record_source(source)
        return nil unless source.is_a?(Hash)

        roster = source["origin"] == "roster"
        row = source["row_number"].to_i
        {
          origin: roster ? "roster" : "resolution",
          source_key: roster ? source["source_key"]&.to_s : nil,
          capture_sha256: roster ? Format.sha256(source["capture_sha256"]) : nil,
          row_number: roster && row.positive? ? row : nil
        }
      end

      def cite(ctx, what, source)
        source = record_source(source)
        from = if source && source[:origin] == "roster" && source[:source_key]
          row = source[:row_number] ? (ctx.fr? ? ", ligne #{source[:row_number]}" : ", row #{source[:row_number]}") : ""
          ctx.fr? ? "; d'après le registre source #{source[:source_key]}#{row}" : "; from roster #{source[:source_key]}#{row}"
        else
          ctx.fr? ? "; établie par la résolution d'entités" : "; from entity resolution"
        end
        lead = ctx.fr? ? "Registre des entités de Build Canada, version #{ctx.release}" : "Build Canada entity registry release #{ctx.release}"
        "#{lead}, #{what}#{from}."
      end

      def json_object(value)
        value = JSON.parse(value) if value.is_a?(String)
        value.is_a?(Hash) ? value : {}
      rescue JSON::ParserError
        {}
      end

      def jurisdiction(value) = value.to_s.downcase.match?(/\A[a-z]{2}(-[a-z0-9]{1,3})?\z/) ? value.to_s.downcase : nil
    end
  end
end
