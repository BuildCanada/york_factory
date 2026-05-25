module Api
  module V1
    module Kpis
      class FactsController < BaseController
        def index
          measure = ::Warehouse::Measure.find(params[:measure_id])
          scope = measure.facts.order(measurement_year: :desc, value_type: :asc)
          scope = scope.where(measurement_year: params[:year]) if params[:year].present?
          scope = scope.where(value_type: params[:value_type]) if params[:value_type].present?

          pagy, facts = pagy(scope, limit: (params[:per_page] || 100).to_i)
          render json: {
            data: facts.map { |f| serialize(f) },
            meta: pagy_metadata(pagy)
          }
        end

        private

        def serialize(fact)
          {
            measure_id: fact.measure_id,
            measurement_year: fact.measurement_year,
            value_type: fact.value_type,
            period_basis: fact.period_basis,
            value_numeric: fact.value_numeric,
            value_text: fact.value_text,
            citation_id: fact.citation_id,
            document_id: fact.document_id
          }
        end
      end
    end
  end
end
