module Api
  module V1
    module Kpis
      class CitationsController < BaseController
        # Nested: GET /api/v1/kpis/measures/:measure_id/citations
        # Top-level: GET /api/v1/kpis/citations (filterable)
        def index
          scope = ::Warehouse::ExtractedObservation.includes(:document, measure: { organization: :jurisdiction })

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
          scope = scope.where(review_status: params[:review_status]) if params[:review_status].present?

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
            period_start: c.period_start,
            period_end: c.period_end,
            period_type: c.period_type,
            value_numeric: c.value_numeric,
            value_text: c.value_text,
            value_raw: c.value_raw,
            unit_raw: c.unit_raw,
            source_page: c.source_page,
            source_section: c.source_section,
            source_table: c.source_table,
            source_chart: c.source_chart,
            evidence_quote: c.evidence_quote,
            extraction_confidence: c.extraction_confidence,
            review_status: c.review_status,
            needs_review: c.needs_review,
            metric_name_raw: c.metric_name_raw,
            geography_name_raw: c.geography_name_raw,
            jurisdiction_name_raw: c.jurisdiction_name_raw,
            reporting_organization_raw: c.reporting_organization_raw,
            responsible_organization_raw: c.responsible_organization_raw,
            observed_organization_raw: c.observed_organization_raw,
            reporting_organization_id: c.reporting_organization_id,
            responsible_organization_id: c.responsible_organization_id,
            observed_organization_id: c.observed_organization_id,
            geo_boundary_id: c.geo_boundary_id,
            jurisdiction_id: c.jurisdiction_id,
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
