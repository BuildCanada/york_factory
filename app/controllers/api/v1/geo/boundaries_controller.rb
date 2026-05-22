module Api
  module V1
    module Geo
      class BoundariesController < ApplicationController
        include Pagy::Method

        def index
          scope = ::Warehouse::GeoBoundary.all
          scope = scope.by_type(params[:boundary_type]) if params[:boundary_type].present?
          scope = scope.in_province(params[:province_code]) if params[:province_code].present?
          scope = scope.search_name(params[:q]) if params[:q].present?
          scope = scope.order(:boundary_type, :geo_uid)

          pagy, boundaries = pagy(scope)

          render json: {
            data: boundaries.map { |b| serialize_boundary(b) },
            pagination: {
              page: pagy.page,
              pages: pagy.pages,
              count: pagy.count,
              per_page: pagy.limit
            }
          }
        end

        private

        def serialize_boundary(boundary)
          {
            id: boundary.id,
            geo_uid: boundary.geo_uid,
            boundary_type: boundary.boundary_type,
            name_en: boundary.name_en,
            name_fr: boundary.name_fr,
            province_code: boundary.province_code,
            population: boundary.population,
            area_sq_km: boundary.area_sq_km,
            census_year: boundary.census_year
          }
        end
      end
    end
  end
end
