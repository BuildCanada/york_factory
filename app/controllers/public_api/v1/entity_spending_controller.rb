module PublicApi
  module V1
    # GET /v1/entities/{id}/spending, /spending/summary and /spending/unlinked
    # (docs/public-interface-design.md §3.4).
    class EntitySpendingController < BaseController
      include PublicApiEntityLookup
      include PublicApiSpendingRows

      operation :index, :listEntitySpending
      operation :summary, :getEntitySpendingSummary
      operation :unlinked, :listEntityUnlinkedSpending

      def index
        check_fields!(SpendingSerializer::RECORD_FIELDS)
        entity = load_entity! or return
        role = parameters["role"]
        proposed = parameters["include_proposed"]
        filters = parameters.values.slice("source", "fiscal_year", "latest_revision_only")
        sort = parameters["sort"]
        rows = spending_query.page(filters:, sort:, limit:, after:, entity: entity.entity_id, role:, include_proposed: proposed)
        page, next_cursor = paginate(rows) { |r| spending_cursor_key(r, sort) }
        count = parameters["count"] == "exact" ? spending_query.count(filters:, entity: entity.entity_id, role:, include_proposed: proposed) : nil
        # Proposed rows are marked in each party's link_status, so their
        # parties are shown (listEntitySpending).
        data = serialize_records(page, show_parties: proposed || expand?("parties"))
        caveats = record_caveats(page, filters)
        caveats << Catalog.caveat(:proposed_included, locale:) if proposed
        render_data({ data:, meta: list_meta(next_cursor:, count:, caveats:), links: page_links(next_cursor) })
      end

      def summary
        entity = load_entity! or return
        role = parameters["role"]
        group_by = ([ "source" ] + Array(parameters["group_by"])).uniq
        by_year = group_by.include?("fiscal_year")
        sources = parameters["source"]
        fiscal_year = parameters["fiscal_year"] && Format.fiscal_year_start(parameters["fiscal_year"])
        rows = if group_by.include?("counterparty")
          spending_query.counterparty_summary(entity.entity_id, role:, by_year:, sources:, fiscal_year:)
        else
          spending_query.summary(entity.entity_id, role:, by_year:, sources:, fiscal_year:)
        end
        if rows == :too_broad
          raise Problem.new(:query_too_broad, "This entity has more than #{FactFactory::SpendingQuery::COUNTERPARTY_ROW_LIMIT} linked rows; group_by=counterparty is limited to fewer. Narrow it with source or fiscal_year, or use the bulk files.")
        end

        counterparties = entity_query.refs(rows.map { |r| r["counterparty_id"] })
        data = rows.map { |r| SpendingSerializer.summary_row(r, counterparty: counterparties[r["counterparty_id"]]) }
        unlinked = spending_query.unlinked_count(entity.entity_id, role:, sources:, fiscal_year:)
        excluded = rows.sum { |r| r["aggregated_excluded"].to_i }
        base = "/v1/entities/#{entity.entity_id}/spending"
        unlinked_url = Links.url("#{base}/unlinked", { "role" => role, "as_of" => release })
        caveats = [
          Catalog.caveat(:not_cross_source_total, locale:),
          Catalog.caveat(:latest_revision_only, locale:),
          Catalog.caveat(:linked_only, locale:, count: unlinked, url: unlinked_url)
        ]
        caveats << Catalog.caveat(:aggregates_excluded, locale:, count: excluded) if excluded.positive?
        caveats << Catalog.caveat(:amount_missing, locale:) if data.any? { |r| r[:amount_missing].positive? }
        data.map { |r| r[:source] }.uniq.each { |s| caveats.concat(source_caveats(s)) }
        render_data({
          data:,
          meta: meta(caveats:).merge(role:, group_by:, aggregated_rows_excluded: excluded, unlinked_occurrences: unlinked),
          links: { self: self_link, unlinked: unlinked_url, records: Links.url(base, { "role" => role, "as_of" => release }) }
        })
      end

      def unlinked
        entity = load_entity! or return
        fiscal_year = parameters["fiscal_year"] && Format.fiscal_year_start(parameters["fiscal_year"])
        parties = spending_query.unlinked(entity.entity_id, role: parameters["role"], sources: parameters["source"], fiscal_year:,
          reasons: parameters["reason"], limit:, after:)
        page, next_cursor = paginate(parties) { |p| [ p.row_id ] }
        records = spending_query.records_for(page)
        data = page.filter_map do |p|
          record = records[[ p.asset_key, p.acquisition, p.spending_row_id ]] or next
          { party: SpendingSerializer.party(p, {}), record: SpendingSerializer.ref(record) }
        end
        render_data({ data:, meta: list_meta(next_cursor:), links: page_links(next_cursor) })
      end
    end
  end
end
