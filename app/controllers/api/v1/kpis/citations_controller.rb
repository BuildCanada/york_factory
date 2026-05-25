module Api
  module V1
    module Kpis
      class CitationsController < BaseController
        def index
          measure = ::Warehouse::Measure.find(params[:measure_id])
          scope = measure.citations.includes(:document)
            .order(measurement_year: :desc, id: :desc)
          scope = scope.where(measurement_year: params[:year]) if params[:year].present?
          scope = scope.where(value_type: params[:value_type]) if params[:value_type].present?

          pagy, citations = pagy(scope, limit: (params[:per_page] || 100).to_i)
          render json: {
            data: citations.map { |c| serialize(c) },
            meta: pagy_metadata(pagy)
          }
        end

        private

        def serialize(c)
          {
            id: c.id,
            measure_id: c.measure_id,
            measurement_year: c.measurement_year,
            value_type: c.value_type,
            period_basis: c.period_basis,
            value_numeric: c.value_numeric,
            value_text: c.value_text,
            value_raw_text: c.value_raw_text,
            page_number: c.page_number,
            notes: c.notes,
            document: c.document && {
              id: c.document.id,
              fiscal_year: c.document.fiscal_year,
              published_at: c.document.published_at,
              doc_url: c.document.doc_url,
              doc_title: c.document.doc_title
            }
          }
        end
      end
    end
  end
end
