module Api
  module V1
    module Kpis
      class CitationsController < BaseController
        # Nested: GET /api/v1/kpis/measures/:measure_id/citations
        # Top-level: GET /api/v1/kpis/citations (filterable)
        def index
          scope = ::Warehouse::MeasureCitation.includes(:document, measure: { organization: :jurisdiction })

          if params[:measure_id].present?
            scope = scope.where(measure_id: params[:measure_id])
          end

          if params[:jurisdiction_slug].present?
            jur = ::Warehouse::Jurisdiction.find_by!(slug: params[:jurisdiction_slug])
            org_ids = ::Warehouse::Organization.where(jurisdiction_id: jur.id).pluck(:id)
            scope = scope.joins(:measure).where("warehouse.measures.organization_id" => org_ids)
          end

          if params[:organization_slug].present?
            org = ::Warehouse::Organization.find_by!(slug: params[:organization_slug])
            scope = scope.joins(:measure).where("warehouse.measures.organization_id" => org.id)
          end

          scope = scope.where(document_id: params[:document_id]) if params[:document_id].present?
          scope = scope.where(measurement_year: params[:year]) if params[:year].present?
          scope = scope.where(value_type: params[:value_type]) if params[:value_type].present?
          scope = scope.where(period_basis: params[:period_basis]) if params[:period_basis].present?
          scope = scope.where(agent_run_id: params[:agent_run_id]) if params[:agent_run_id].present?

          scope = scope.order(measurement_year: :desc, id: :desc)
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
            agent_run_id: c.agent_run_id,
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
