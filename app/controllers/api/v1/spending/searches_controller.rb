module Api
  module V1
    module Spending
      class SearchesController < ApplicationController
        rescue_from ::Warehouse::Spending::Search::InvalidRequest, ArgumentError do |error|
          render json: { error: "invalid_search", details: error.message }, status: :unprocessable_entity
        end

        def index
          result = ::Warehouse::Spending::Search.new(search_parameters).call

          render json: {
            data: result.records.map { |award| ::Warehouse::Spending::Serializer.search_document(award) },
            facets: result.facets,
            meta: {
              total: result.found,
              page: result.page,
              per_page: result.per_page,
              pages: result.per_page.zero? ? 0 : (result.found.to_f / result.per_page).ceil,
              query: result.query,
              elapsed_ms: result.elapsed_ms
            }
          }
        end

        private

        def search_parameters
          params.permit(:q, :page, :per_page, :filter_by, :facet_by, :facet_query, :sort_by, :max_facet_values).to_h
        end
      end
    end
  end
end
