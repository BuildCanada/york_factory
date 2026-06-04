module Api
  module V1
    module Kpis
      module Admin
        class SourceFootnotesController < BaseController
          # POST /api/v1/kpis/admin/documents/:document_id/footnotes
          # Body: { footnote_text, page?, marker?, agent_run_id? }
          def create
            doc = ::Warehouse::KpiDocument.find(params[:document_id])
            footnote = doc.source_footnotes.create!(
              footnote_text: params.fetch(:footnote_text),
              page:    params[:page],
              marker:  params[:marker],
              agent_run_id: params[:agent_run_id]
            )
            render json: serialize(footnote), status: :created
          rescue ActionController::ParameterMissing => e
            render json: { error: e.message }, status: :unprocessable_entity
          end

          private

          def serialize(f)
            {
              id: f.id,
              document_id: f.document_id,
              page: f.page,
              marker: f.marker,
              footnote_text: f.footnote_text,
              agent_run_id: f.agent_run_id,
              created_at: f.created_at
            }
          end
        end
      end
    end
  end
end
