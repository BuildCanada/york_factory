module Mcp
  module Tools
    # entity_spending: GET /v1/entities/{id}/spending/summary and the entity's
    # largest rows (GET /v1/entities/{id}/spending?sort=-amount).
    class EntitySpending < Base
      tool_name "entity_spending"
      title "Money an entity received or paid"
      GROUPS = %w[source fiscal_year counterparty].freeze

      description <<~TEXT.squish
        Federal money one entity received (role recipient, the default) or paid out (role payer), from every
        spending source Build Canada publishes: grants and contributions, contracts, transfer payments, research
        council awards and Global Affairs projects. Returns a summary with one row per source (and per fiscal year,
        or per counterparty, as group_by asks) and the entity's largest individual rows, each with its cite.
        Amounts from different sources overlap; never add them. Call describe_data("spending semantics") before
        totalling. Report each source separately with its measure: agreement_value (grants: agreements, not money
        paid), contract_value, payments_or_expenditure, award_amount or commitment. Within one source the summary
        already applies the rules: only the latest revision of each agreement, aggregate rows left out, blank
        amounts counted in amount_missing and never as zero. Amounts are decimal strings in the row's currency
        (almost always CAD). Only rows linked to this entity are counted; meta.unlinked_occurrences counts rows
        that name it but are not linked, so say when it is not zero. Get the id from search_entities; a
        predecessor's money is under its own id (get_entity with include lineage). Use group_by ["source",
        "counterparty"] and role payer for "who did this department fund". Cite the summary URL and the release
        given in citations. Costs 4 request units (3 with top 0).
      TEXT
      input_schema(
        properties: {
          id: Arguments.entity_id("The entity's 26-character ID or gid, from search_entities."),
          role: Schemas.parameter("getEntitySpendingSummary", "role", description:
            "recipient: money the entity received (default). payer: money it paid out, for a department or agency."),
          group_by: { type: "array", uniqueItems: true, items: { type: "string", enum: GROUPS }, default: %w[source fiscal_year],
                      description: "How to group the summary. source is always included. counterparty groups by the " \
                                   "linked payer (for a recipient) or recipient (for a payer)." },
          fiscal_year: Arguments.fiscal_year("getEntitySpendingSummary"),
          source: Arguments.sources("getEntitySpendingSummary"),
          top: { type: "integer", minimum: 0, maximum: 20, default: 5,
                 description: "How many of the largest individual rows (latest revisions only) to include; 0 for none." },
          as_of: Arguments.as_of("getEntitySpendingSummary")
        },
        required: [ "id" ]
      )
      output_schema Schemas.output(
        properties: {
          "summary" => Schemas.ref("SpendingSummaryResponse"),
          "top_records" => { "anyOf" => [ Schemas.ref("SpendingRecordListResponse"), { "type" => "null" } ],
                             "description" => "The entity's largest rows in the same filters, largest first, or null with top 0." },
          "redirected_from" => { "type" => [ "string", "null" ] },
          "citations" => { "type" => "array", "items" => { "type" => "string" } }
        },
        required: %w[summary top_records redirected_from citations]
      )

      def self.perform(ctx, id:, role: "recipient", group_by: nil, fiscal_year: nil, source: nil, top: 5, as_of: nil)
        path = "#{Arguments.entity_path(id)}/spending/summary"
        response = ctx.api.get(path, operation: "getEntitySpendingSummary", role:, group_by:, fiscal_year:, source:, as_of:)
        redirected_from = nil
        if response.redirect?
          redirected_from = PublicApi::Format.entity_gid(PublicApi::Format.bare_id(id, "Entity"))
          path, params = Arguments.split(response.location)
          response = ctx.api.get(path, operation: "getEntitySpendingSummary", **params)
        end
        summary = expect_ok!(response).body
        release = release_of(summary)
        records = nil
        if top.to_i.positive?
          records = expect_ok!(ctx.api.get(path.delete_suffix("/summary"), operation: "listEntitySpending", role:, fiscal_year:, source:,
            sort: "-amount", latest_revision_only: true, limit: top, as_of: release)).body
        end
        citations = [ operation_citation(summary.dig("links", "self"), release) ] + Array(records&.dig("data")).map { |r| r["cite"] }
        { "summary" => summary, "top_records" => records, "redirected_from" => redirected_from, "citations" => citations }
      end

      def self.summary(result)
        summary = result["summary"]
        meta = summary["meta"]
        lines = [ "Spending as #{meta['role']}, Build Canada data release #{meta['release']}, grouped by #{meta['group_by'].join(', ')}." ]
        lines << "Followed #{result['redirected_from']}, which was merged, to its survivor." if result["redirected_from"]
        if summary["data"].empty?
          lines << "No linked rows."
        else
          lines << "One line per group. Never add amounts across sources:"
          summary["data"].each do |row|
            group = [ row["source"], row["fiscal_year"], row.dig("counterparty", "name") ].compact.join(", ")
            missing = row["amount_missing"].positive? ? ", #{row['amount_missing']} with blank amounts" : ""
            lines << "- #{group}: #{row['amount']} #{row['currency']} (#{row['measure']}), #{row['records']} rows, #{row['agreements']} agreements#{missing}"
          end
        end
        lines << "Unlinked rows naming this entity, not counted: #{meta['unlinked_occurrences']}." if meta["unlinked_occurrences"].to_i.positive?
        lines << "Caveats (act on each):" << caveat_lines(meta["caveats"]) if meta["caveats"].present?
        if (records = result["top_records"]) && records["data"].any?
          lines << "Largest rows:"
          records["data"].each do |r|
            lines << "- #{r['amount'] || 'blank'} #{r['currency']} #{r['source']} #{r['fiscal_year']}: #{r['title'] || r['program'] || 'untitled'} " \
                     "(#{r['payer'] || 'payer unknown'} to #{r['recipient'] || Array(r['recipients']).join('; ').presence || 'recipient unknown'})#{SearchSpending.flags(r)} #{r['id']}"
          end
        end
        lines.flatten.join("\n")
      end
    end
  end
end
