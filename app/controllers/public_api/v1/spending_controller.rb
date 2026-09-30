module PublicApi
  module V1
    # GET /v1/spending, /v1/spending/sources and /v1/spending/{id}.
    class SpendingController < BaseController
      include PublicApiEntityLookup
      include PublicApiSpendingRows

      operation :index, :listSpending
      operation :sources, :listSpendingSources
      operation :show, :getSpendingRecord

      def index
        check_fields!(SpendingSerializer::RECORD_FIELDS)
        filters = parameters.values.slice("source", "payer", "recipient", "fiscal_year", "record_type", "amount_min", "amount_max", "q",
          "latest_revision_only", "include_aggregated")
        sort = parameters["sort"]
        rows = spending_query.page(filters:, sort:, limit:, after:)
        page, next_cursor = paginate(rows) { |r| spending_cursor_key(r, sort) }
        count = parameters["count"] == "exact" ? spending_query.count(filters:) : nil
        data = serialize_records(page, show_parties: expand?("parties"))
        caveats = [ Catalog.caveat(:not_cross_source_total, locale:) ] + record_caveats(page, filters)
        render_data({ data:, meta: list_meta(next_cursor:, count:, caveats:), links: page_links(next_cursor) })
      end

      def sources
        list = Catalog.sources.values.filter_map do |source|
          snapshot = FactFactory::ReleaseQuery.snapshot_for(release, asset_key: source.asset, acquisition: "live")
          snapshot && SpendingSerializer.source_object(source, context, snapshot_id: snapshot)
        end.sort_by { |s| s[:source] }
        list = list.select { |s| s[:source] > after.first } if after
        page, next_cursor = paginate(list.first(limit + 1)) { |s| [ s[:source] ] }
        render_data({ data: page, meta: list_meta(next_cursor:, caveats: [ Catalog.caveat(:not_cross_source_total, locale:) ]), links: page_links(next_cursor) })
      end

      def show
        key = Format.bare_id(parameters["id"], "SpendingRecord")
        record = spending_query.find(key) or not_found!("spending record #{key}")
        (data,) = serialize_records([ record ], show_parties: true)
        render_data({ data:, meta: meta(caveats: record_caveats([ record ], {})), links: { self: self_link } })
      end
    end
  end
end
