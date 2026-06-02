module Api
  module V1
    module Kpis
      class FactsController < BaseController
        # Nested:    GET /api/v1/kpis/measures/:measure_id/facts
        # Top-level: GET /api/v1/kpis/facts (filterable, cross-measure)
        def index
          scope = ::Warehouse::MeasureFact.all

          if params[:measure_id].present?
            scope = scope.where(measure_id: params[:measure_id])
          end

          if params[:jurisdiction_slug].present? || params[:organization_slug].present?
            org_ids = if params[:organization_slug].present?
              [ ::Warehouse::Organization.find_by!(slug: params[:organization_slug]).id ]
            else
              jur = ::Warehouse::Jurisdiction.find_by!(slug: params[:jurisdiction_slug])
              ::Warehouse::Organization.where(jurisdiction_id: jur.id).pluck(:id)
            end
            measure_ids = ::Warehouse::Measure.where(organization_id: org_ids).pluck(:id)
            scope = scope.where(measure_id: measure_ids)
          end

          scope = scope.where(measurement_year: params[:year]) if params[:year].present?
          scope = scope.where(value_type: params[:value_type]) if params[:value_type].present?
          scope = scope.where(period_basis: params[:period_basis]) if params[:period_basis].present?

          scope = scope.order(measurement_year: :desc, measure_id: :asc, value_type: :asc)
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
            canonical_observation_id: fact.canonical_observation_id,
            extracted_observation_id: fact.extracted_observation_id,
            document_id: fact.document_id,
            observed_organization_id: fact.observed_organization_id,
            jurisdiction_id: fact.jurisdiction_id,
            status: fact.status,
            vintage_date: fact.vintage_date
          }
        end
      end
    end
  end
end
