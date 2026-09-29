module Mcp
  module Tools
    # search_spending: GET /v1/spending.
    class SearchSpending < Base
      tool_name "search_spending"
      title "Search spending records"
      description <<~TEXT.squish
        Find individual federal spending rows (contracts, grants, contributions, transfer payments, research awards,
        international projects) by words in their title, description, program or party names (query), by linked
        payer or recipient entity ID (from search_entities; names are not accepted there, use query for a name),
        by source, fiscal year, record type or amount. Each row has its amount as a decimal string with its currency
        and measure, the source's note on what the amount means, provenance and a ready-to-paste cite. Amounts from
        different sources overlap; never add them. Call describe_data("spending semantics") before totalling. Rows
        sharing a canonical_id are revisions of one agreement: never add them either; set latest_revision_only true
        to keep only the latest. For an entity's totals use entity_spending instead, which applies these rules.
        Individuals' postal codes are cut to the first three characters; there are no street addresses. Pages hold
        10 rows by default; pass next_cursor as cursor for more. Costs 1 request unit per page of 50 or fewer.
      TEXT
      input_schema(
        properties: {
          query: Schemas.parameter("listSpending", "q", description:
            "Words to find in the title, description, program or party names as published, e.g. \"cultural spaces\" or a recipient's name."),
          payer: Arguments.entity_id("Only rows paid by this linked entity (ID or gid from search_entities)."),
          recipient: Arguments.entity_id("Only rows received by this linked entity (ID or gid from search_entities)."),
          source: Arguments.sources("listSpending"),
          fiscal_year: Arguments.fiscal_year("listSpending"),
          record_type: Schemas.parameter("listSpending", "record_type", description: "Only this kind of row."),
          amount_min: { type: [ "string", "number" ], description: "Only rows with at least this amount, in the row's currency, e.g. \"100000.00\"." },
          amount_max: { type: [ "string", "number" ], description: "Only rows with at most this amount." },
          latest_revision_only: { type: "boolean", default: false, description: "Keep only the latest revision of each agreement." },
          sort: Schemas.parameter("listSpending", "sort", description: "Order: -amount for largest first, -date for newest first; id (default) is stable."),
          as_of: Arguments.as_of("listSpending"),
          limit: { type: "integer", minimum: 1, maximum: 50, default: 10, description: "Rows per page (1 to 50)." },
          cursor: Arguments.cursor
        }
      )
      output_schema Schemas.output(
        description: "The /v1/spending response (data, meta, links) plus citations.",
        properties: {
          "data" => { "type" => "array", "items" => Schemas.ref("SpendingRecord") },
          "meta" => Schemas.ref("ListMeta"),
          "links" => Schemas.ref("PageLinks"),
          "citations" => { "type" => "array", "items" => { "type" => "string" } }
        },
        required: %w[data meta links citations]
      )

      def self.perform(ctx, query: nil, amount_min: nil, amount_max: nil, limit: 10, **filters)
        response = expect_ok!(ctx.api.get("/v1/spending", operation: "listSpending", q: query,
          amount_min: amount(amount_min), amount_max: amount(amount_max), limit:, **filters.slice(*%i[payer recipient source fiscal_year
                                                                                                        record_type latest_revision_only sort as_of cursor])))
        body = response.body
        body.merge("citations" => body["data"].map { |r| r["cite"] })
      end

      # A number or numeric string as the contract's Amount ("125000.00").
      def self.amount(value)
        return nil if value.nil?
        return value if value.is_a?(String) && value.match?(/\A-?\d+\.\d{2,6}\z/)

        PublicApi::Format.amount(BigDecimal(value.to_s))
      rescue ArgumentError
        value.to_s
      end

      # Why a row may not count toward a total, in words.
      def self.flags(r)
        notes = []
        notes << "an earlier revision" unless r["is_latest_revision"]
        notes << "an aggregate row" if r["is_aggregated"]
        notes << "an archive import that may repeat a live row" if r["acquisition"] == "archive_import"
        notes.any? ? " [#{notes.join('; ')}]" : ""
      end

      def self.summary(result)
        meta = result["meta"]
        rows = result["data"]
        lines = [ "#{rows.size} row#{'s' unless rows.one?} (Build Canada data release #{meta['release']}). Never add amounts across sources or revisions." ]
        rows.each do |r|
          lines << "- #{r['amount'] || 'blank amount'} #{r['currency']} (#{r['measure']}) #{r['source']} #{r['fiscal_year']}: " \
                   "#{r['title'] || r['program'] || 'untitled'}; #{r['payer'] || 'payer unknown'} to " \
                   "#{r['recipient'] || Array(r['recipients']).join('; ').presence || 'recipient unknown'}#{flags(r)}. #{r['id']}"
        end
        lines << "Caveats (act on each):" << caveat_lines(meta["caveats"]) if meta["caveats"].present?
        lines << "More rows: call again with cursor=\"#{meta['next_cursor']}\"." if meta["next_cursor"]
        lines.flatten.join("\n")
      end
    end
  end
end
