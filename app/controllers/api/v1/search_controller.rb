module Api
  module V1
    class SearchController < ApplicationController
      before_action :doorkeeper_authorize!

      rescue_from Search::QueryCompiler::InvalidDefinition, ArgumentError do |error|
        render json: { error: "invalid_search", details: error.message }, status: :unprocessable_entity
      end

      def preview
        definition = params.require(:definition).to_unsafe_h
        limit = params.fetch(:limit, 25).to_i.clamp(1, 100)
        result = Search::QueryRunner.new.call(definition, limit:)
        render json: {
          data: result.rows,
          meta: { query_count: result.query_count, billing: result.billing, performance: result.performance }
        }
      end

      def realm
        contract = Search::Realms.fetch(params[:realm])
        render json: {
          realm: params[:realm],
          version: contract.version,
          record_types: contract.allowed_record_types,
          filter_fields: contract.filter_fields,
          facet_fields: contract.facet_fields
        }
      end
    end
  end
end
