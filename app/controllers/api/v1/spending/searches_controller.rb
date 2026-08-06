module Api
  module V1
    module Spending
      class SearchesController < ApplicationController
        wrap_parameters false

        ALLOWED_PARAMETERS = %i[
          aggregate_by compute_attributes distance_metric exclude_attributes filters
          group_by include_attributes limit rank_by top_k vector_encoding
        ].freeze
        MAX_LIMIT = 250
        SCOPE_FILTERS = [
          [ "realm", "Eq", "government_spending" ],
          [ "visibility", "Eq", "public" ]
        ].freeze

        rescue_from ArgumentError, Turbopuffer::Errors::ConversionError,
          Turbopuffer::Errors::BadRequestError do |error|
          render json: { error: "invalid_search", details: error.message }, status: :unprocessable_entity
        end

        def create
          response = namespace.query(**query_parameters, consistency: { level: :strong })
          render json: response.respond_to?(:to_h) ? response.to_h : response
        end

        private

        def namespace
          Search.turbopuffer_namespace
        end

        def query_parameters
          body = request.request_parameters
          raise ArgumentError, "query body must be an object" unless body.is_a?(Hash)

          query = body.deep_symbolize_keys
          unknown = query.keys - ALLOWED_PARAMETERS
          raise ArgumentError, "unsupported parameters: #{unknown.join(', ')}" if unknown.any?

          validate_bound!(query, :limit)
          validate_bound!(query, :top_k)
          filters = SCOPE_FILTERS.map(&:dup)
          filters << query[:filters] if query[:filters].present?
          query.merge(filters: [ "And", filters ])
        end

        def validate_bound!(query, key)
          return unless query.key?(key)

          value = Integer(query[key])
          raise ArgumentError, "#{key} must be between 0 and #{MAX_LIMIT}" unless value.between?(0, MAX_LIMIT)

          query[key] = value
        end
      end
    end
  end
end
