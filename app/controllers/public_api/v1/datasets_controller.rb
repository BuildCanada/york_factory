module PublicApi
  module V1
    # GET /v1/datasets and /v1/datasets/{asset_key}.
    class DatasetsController < BaseController
      operation :index, :listDatasets
      operation :show, :getDataset

      def index
        prefix = parameters["prefix"].to_s
        all = CatalogSerializer.datasets(context).select { |d| d[:asset_key].start_with?(prefix) }
        all = all.select { |d| d[:asset_key] > after.first } if after
        page, next_cursor = paginate(all.first(limit + 1)) { |d| [ d[:asset_key] ] }
        render_data({ data: page, meta: list_meta(next_cursor:), links: page_links(next_cursor) })
      end

      def show
        key = parameters["asset_key"]
        dataset = CatalogSerializer.datasets(context).find { |d| d[:asset_key] == key } or not_found!("dataset #{key}")
        render_data({ data: dataset, meta: meta, links: { self: dataset[:links][:self] } })
      end
    end
  end
end
