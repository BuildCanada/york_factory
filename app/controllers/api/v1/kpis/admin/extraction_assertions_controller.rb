module Api
  module V1
    module Kpis
      module Admin
        class ExtractionAssertionsController < BaseController
          # POST /api/v1/kpis/admin/extracted_observations/:extracted_observation_id/assertions
          # Body: { assertion_type, assertion_text, confidence?, evidence_quote?, source_page? }
          def create
            observation = ::Warehouse::ExtractedObservation.find(params[:extracted_observation_id])
            assertion = observation.extraction_assertions.create!(
              assertion_type: params.fetch(:assertion_type),
              assertion_text: params.fetch(:assertion_text),
              confidence:     params[:confidence],
              evidence_quote: params[:evidence_quote],
              source_page:    params[:source_page]
            )
            render json: serialize(assertion), status: :created
          rescue ActionController::ParameterMissing => e
            render json: { error: e.message }, status: :unprocessable_entity
          end

          private

          def serialize(a)
            {
              id: a.id,
              extracted_observation_id: a.extracted_observation_id,
              assertion_type: a.assertion_type,
              assertion_text: a.assertion_text,
              confidence: a.confidence,
              evidence_quote: a.evidence_quote,
              source_page: a.source_page,
              created_at: a.created_at
            }
          end
        end
      end
    end
  end
end
