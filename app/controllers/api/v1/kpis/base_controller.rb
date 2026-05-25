module Api
  module V1
    module Kpis
      class BaseController < ApplicationController
        include Pagy::Method

        rescue_from ActiveRecord::RecordNotFound do |_e|
          render json: { error: "Not found" }, status: :not_found
        end

        private

        def pagy_metadata(pagy)
          { page: pagy.page, pages: pagy.pages, count: pagy.count, per_page: pagy.limit }
        end

        def serialize_unit(unit)
          {
            id: unit.id,
            symbol: unit.symbol,
            kind: unit.kind,
            base_unit: unit.base_unit,
            scale: unit.scale,
            currency_code: unit.currency_code,
            denominator_unit: unit.denominator_unit,
            denominator_scale: unit.denominator_scale
          }
        end

        def serialize_organization_summary(org)
          {
            id: org.id,
            slug: org.slug,
            canonical_name: org.canonical_name,
            active_from_year: org.active_from_year,
            active_to_year: org.active_to_year
          }
        end
      end
    end
  end
end
