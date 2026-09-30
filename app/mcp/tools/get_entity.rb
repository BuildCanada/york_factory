module Mcp
  module Tools
    # get_entity: GET /v1/entities/{id}, with identifiers and relationships
    # (expand) and lineage (/lineage, both directions).
    class GetEntity < Base
      tool_name "get_entity"
      title "Get an entity"
      INCLUDES = %w[identifiers relationships lineage].freeze

      description <<~TEXT.squish
        Read one entity from the Build Canada registry by its ID (from search_entities): its names in English and
        French, class and subtype, jurisdiction, status and valid dates, and optionally its identifiers (business
        numbers, band numbers, census codes, with the source of each), its relationships (who governs it, what it
        reports to, where it is located; up to 50) and its lineage (the entities it succeeded, such as towns
        amalgamated into it, and what succeeded it). Use lineage to answer questions that span renames and
        amalgamations: a predecessor's spending is its own, under its own ID, so ask entity_spending for each one
        and report them separately. A merged (duplicate) ID is followed to its survivor, and redirected_from says
        so. A dissolved entity has status dissolved and valid_to set. Every
        result has a cite to quote and the release it answered from. Costs 1 request unit, plus 2 with lineage.
      TEXT
      input_schema(
        properties: {
          id: Arguments.entity_id("The entity's 26-character ID or its gid (gid://buildcanada/Entity/…), from search_entities."),
          include: { type: "array", items: { type: "string", enum: INCLUDES }, uniqueItems: true,
                     description: "What to add: identifiers, relationships and/or lineage (predecessors and successors)." },
          as_of: Arguments.as_of("getEntity")
        },
        required: [ "id" ]
      )
      output_schema Schemas.output(
        properties: {
          "entity" => Schemas.ref("EntityResponse"),
          "lineage" => {
            "type" => [ "object", "null" ],
            "description" => "With include lineage: the steps back to predecessors and forward to successors, nearest first.",
            "properties" => {
              "predecessors" => { "type" => "array", "items" => Schemas.ref("LineageStep") },
              "successors" => { "type" => "array", "items" => Schemas.ref("LineageStep") }
            }
          },
          "redirected_from" => { "type" => [ "string", "null" ], "description" => "The merged ID asked for, when it was followed to its survivor." },
          "citations" => { "type" => "array", "items" => { "type" => "string" } }
        },
        required: %w[entity lineage redirected_from citations]
      )

      def self.perform(ctx, id:, include: [], as_of: nil)
        include = Array(include)
        expand = include & %w[identifiers relationships]
        response = ctx.api.get(Arguments.entity_path(id), operation: "getEntity", expand: expand.presence, as_of:)
        redirected_from = nil
        if response.redirect?
          redirected_from = PublicApi::Format.entity_gid(PublicApi::Format.bare_id(id, "Entity"))
          path, params = Arguments.split(response.location)
          response = ctx.api.get(path, operation: "getEntity", **params)
        end
        entity = expect_ok!(response).body
        release = release_of(entity)
        lineage = nil
        if include.include?("lineage")
          path = "#{Arguments.entity_path(entity.dig('data', 'id'))}/lineage"
          lineage = %w[predecessors successors].to_h do |direction|
            steps = expect_ok!(ctx.api.get(path, operation: "getEntityLineage", direction:, as_of: release, limit: 50)).body["data"]
            [ direction, steps ]
          end
        end
        { "entity" => entity, "lineage" => lineage, "redirected_from" => redirected_from, "citations" => [ entity.dig("data", "cite") ] }
      end

      def self.summary(result)
        e = result.dig("entity", "data")
        lines = []
        lines << "Followed #{result['redirected_from']}, which was merged, to its survivor." if result["redirected_from"]
        kind = [ e["entity_class"], e["subtype"] ].compact.join("/")
        lines << "#{e['name']}#{" (#{e['name_fr']})" if e['name_fr']} — #{kind}, #{e['jurisdiction'] || 'no jurisdiction'}, #{e['status']}, #{e['id']}"
        dates = [ e["valid_from"] && "from #{e['valid_from']}", e["valid_to"] && "to #{e['valid_to']}" ].compact
        lines << "Valid #{dates.join(' ')}." if dates.any?
        lines << "Also known as: #{e['aliases'].join('; ')}." if e["aliases"].present?
        Array(e["identifiers"]).each { |i| lines << "Identifier #{i['namespace']} #{i['value']}#{' (unverified)' unless i['verified']}" }
        Array(e["relationships"]).each do |r|
          other = r.dig("object", "name") || r["object_ref"] || r["object_id"]
          lines << "#{r['direction'] == 'out' ? 'It' : other} #{r['predicate'].tr('_', ' ')} #{r['direction'] == 'out' ? other : 'it'}#{" (#{r['valid_from']} to #{r['valid_to'] || 'now'})" if r['valid_from'] || r['valid_to']}"
        end
        if (lineage = result["lineage"])
          lineage.each do |direction, steps|
            next if steps.empty?

            names = steps.map { |s| "#{s.dig('entity', 'name')} (#{s.dig('entity', 'id')}#{", #{s['event']}" if s['event']}#{", #{s['effective_date']}" if s['effective_date']})" }
            lines << "#{direction.capitalize}: #{names.join('; ')}"
          end
        end
        lines << "Build Canada data release #{result.dig('entity', 'meta', 'release')}."
        lines.join("\n")
      end
    end
  end
end
