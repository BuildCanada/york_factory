module Api
  module V1
    module Geo
      class CrosswalkController < ApplicationController
        def show
          source_boundary = Warehouse::GeoBoundary.find_by!(
            geo_uid: params[:geo_uid],
            boundary_type: params[:source_type]
          )

          crosswalks = Warehouse::GeoCrosswalk.where(source_id: source_boundary.id)
          crosswalks = crosswalks.to_type(params[:target_type]) if params[:target_type].present?

          min_weight = (params[:min_weight] || 0.01).to_f
          crosswalks = crosswalks.where("weight_source_to_target >= ?", min_weight)
          crosswalks = crosswalks.order(weight_source_to_target: :desc).includes(:target)

          render json: {
            source: serialize_boundary(source_boundary),
            crosswalks: crosswalks.map { |cw| serialize_crosswalk(cw) }
          }
        rescue ActiveRecord::RecordNotFound
          render json: { error: "Boundary not found" }, status: :not_found
        end

        private

        def serialize_boundary(boundary)
          {
            geo_uid: boundary.geo_uid,
            boundary_type: boundary.boundary_type,
            name_en: boundary.name_en,
            name_fr: boundary.name_fr,
            population: boundary.population,
            province_code: boundary.province_code
          }
        end

        def serialize_crosswalk(cw)
          {
            target: serialize_boundary(cw.target),
            weight: cw.weight_source_to_target,
            overlap_population: cw.overlap_population,
            da_count: cw.da_count
          }
        end
      end
    end
  end
end
