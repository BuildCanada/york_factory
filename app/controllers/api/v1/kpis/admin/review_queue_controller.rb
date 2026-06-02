module Api
  module V1
    module Kpis
      module Admin
        class ReviewQueueController < BaseController
          # GET /api/v1/kpis/admin/review_queue
          # Filters: jurisdiction_slug, organization_slug, measure_id, document_id,
          # agent_run_id, min_severity, has_open_flags
          def index
            scope = ::Warehouse::HumanReviewQueueEntry.includes(:measure, :document)
            scope = scope.where(measure_id: params[:measure_id])             if params[:measure_id].present?
            scope = scope.where(document_id: params[:document_id])           if params[:document_id].present?
            scope = scope.where(agent_run_id: params[:agent_run_id])         if params[:agent_run_id].present?

            if params[:jurisdiction_slug].present?
              jur = ::Warehouse::Jurisdiction.find_by!(slug: params[:jurisdiction_slug])
              org_ids = ::Warehouse::Organization.where(jurisdiction_id: jur.id).pluck(:id)
              measure_ids = ::Warehouse::Measure.where(organization_id: org_ids).pluck(:id)
              scope = scope.where(measure_id: measure_ids)
            end

            if params[:organization_slug].present?
              org = ::Warehouse::Organization.find_by!(slug: params[:organization_slug])
              measure_ids = ::Warehouse::Measure.where(organization_id: org.id).pluck(:id)
              scope = scope.where(measure_id: measure_ids)
            end

            if (min_rank = severity_rank(params[:min_severity]))
              scope = scope.where("highest_open_severity_rank >= ?", min_rank)
            end

            scope = scope.where(has_open_flags: true) if ActiveModel::Type::Boolean.new.cast(params[:has_open_flags])

            pagy, rows = pagy(scope.by_severity, limit: (params[:per_page] || 50).to_i)
            render json: { data: rows.map { |r| serialize(r) }, meta: pagy_metadata(pagy) }
          end

          private

          SEVERITY_RANKS = ::Warehouse::ObservationReviewFlag::SEVERITY_RANK

          def severity_rank(label)
            return nil if label.blank?
            SEVERITY_RANKS[label]
          end

          def serialize(r)
            {
              extracted_observation_id: r.extracted_observation_id,
              measure_id: r.measure_id,
              document_id: r.document_id,
              agent_run_id: r.agent_run_id,
              measurement_year: r.measurement_year,
              value_type: r.value_type,
              period_basis: r.period_basis,
              value_numeric: r.value_numeric,
              value_text: r.value_text,
              value_raw: r.value_raw,
              metric_name_raw: r.metric_name_raw,
              evidence_quote: r.evidence_quote,
              source_page: r.source_page,
              source_section: r.source_section,
              source_table: r.source_table,
              extraction_confidence: r.extraction_confidence,
              review_status: r.review_status,
              needs_review: r.needs_review,
              open_flag_count: r.open_flag_count,
              highest_open_severity: r.highest_open_severity,
              created_at: r.created_at,
              measure: r.measure && {
                id: r.measure.id, canonical_name: r.measure.canonical_name, slug: r.measure.slug
              },
              document: r.document && {
                id: r.document.id, doc_url: r.document.doc_url, doc_title: r.document.doc_title
              }
            }
          end
        end
      end
    end
  end
end
