module Mcp
  module Tools
    # search_entities: GET /v1/search.
    class SearchEntities < Base
      tool_name "search_entities"
      title "Search entities"
      description <<~TEXT.squish
        Find a Canadian organization, government body, jurisdiction, Indigenous government or person in the Build
        Canada entity registry, by identifier or by name. Use it first, to turn a name into the entity ID the other tools take.
        An identifier (a CRA business number BN9 or BN15, a corporation number, a First Nations band number, an LEI,
        a StatCan census code) matches exactly; otherwise names and aliases match after normalization. Each result
        has match.kind: identifier or exact are matches; with fuzzy=true, fuzzy results are similar names to check,
        not matches, so say so if you rely on one. Results are best first; prefer a precise name with its place
        ("Town of Diamond Valley", jurisdiction "ca-ab"). Persons are searched like any other entity. Returns entity
        references (id, name, class, subtype, jurisdiction, status) and the release that answered: pass that release
        as as_of on later calls. Costs 3 request units.
      TEXT
      input_schema(
        properties: {
          query: Schemas.parameter("searchEntities", "q", description:
            "A name (\"Canadian Heritage\") or an identifier (\"107511586\", a BN9). At least 2 letters or digits."),
          class: Schemas.parameter("searchEntities", "class", description:
            "Only this kind of entity: government_org (departments, agencies, municipalities), organization " \
            "(charities, companies, non-profits), jurisdiction, government_enterprise, indigenous_government, or person."),
          jurisdiction: Schemas.parameter("searchEntities", "jurisdiction", description:
            "Only entities in this jurisdiction: \"ca\" for federal, \"ca-ab\" for Alberta, \"ca-on\" for Ontario, and so on."),
          fuzzy: { type: "boolean", default: false, description:
            "Also return similar names (trigram similarity), marked match.kind fuzzy. Use it when an exact search finds nothing." },
          as_of: Arguments.as_of("searchEntities"),
          limit: { type: "integer", minimum: 1, maximum: 50, default: 10, description: "Results per page (1 to 50)." },
          cursor: Arguments.cursor
        },
        required: [ "query" ]
      )
      output_schema Schemas.output(
        description: "The /v1/search response (data, meta, links) plus citations.",
        properties: {
          "data" => { "type" => "array", "items" => Schemas.ref("SearchHit"), "description" => "Results, best first." },
          "meta" => Schemas.ref("ListMeta"),
          "links" => Schemas.ref("PageLinks"),
          "citations" => { "type" => "array", "items" => { "type" => "string" } }
        },
        required: %w[data meta links citations]
      )

      def self.perform(ctx, query:, fuzzy: false, limit: 10, cursor: nil, as_of: nil, **filters)
        response = expect_ok!(ctx.api.get("/v1/search", operation: "searchEntities", q: query, mode: fuzzy ? "fuzzy" : nil,
          class: filters[:class], jurisdiction: filters[:jurisdiction], as_of:, limit:, cursor:))
        body = response.body
        body.merge("citations" => [ operation_citation(body.dig("links", "self"), release_of(body)) ])
      end

      def self.summary(result)
        release = result.dig("meta", "release")
        hits = result["data"]
        return "No entities matched (release #{release}). Try fuzzy=true, another spelling, or an identifier." if hits.empty?

        lines = hits.each_with_index.map do |hit, i|
          e = hit["entity"]
          m = hit["match"]
          kind = [ e["entity_class"], e["subtype"] ].compact.join("/")
          place = [ e["jurisdiction"], e["status"] == "active" ? nil : e["status"] ].compact.join(", ")
          "#{i + 1}. #{e['name']} (#{kind}; #{place}) #{e['id']} — #{m['kind']} match on #{m['matched_on']}#{m['kind'] == 'fuzzy' ? " (score #{m['score']}, a candidate to check)" : ''}"
        end
        text = "#{hits.size} result#{'s' unless hits.one?} (Build Canada data release #{release}):\n#{lines.join("\n")}"
        cursor = result.dig("meta", "next_cursor")
        text += "\nMore results: call again with cursor=\"#{cursor}\" and as_of=\"#{release}\"." if cursor
        text
      end
    end
  end
end
