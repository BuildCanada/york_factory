module Api
  module V1
    module Kpis
      class JurisdictionsController < BaseController
        def index
          jurisdictions = ::Warehouse::Jurisdiction.order(:name)
          render json: { data: jurisdictions.map { |j| serialize(j) } }
        end

        def show
          jurisdiction = ::Warehouse::Jurisdiction.find_by!(slug: params[:slug])
          render json: serialize(jurisdiction)
        end

        private

        def serialize(j)
          {
            id: j.id,
            slug: j.slug,
            name: j.name,
            code: j.code,
            level: j.level,
            region_code: j.region_code,
            fiscal_year_start_month: j.fiscal_year_start_month,
            default_currency: j.default_currency
          }
        end
      end
    end
  end
end
