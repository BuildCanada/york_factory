module Api
  module V1
    module Kpis
      module Admin
        class ObservationReviewFlagsController < BaseController
          # POST /api/v1/kpis/admin/extracted_observations/:extracted_observation_id/review_flags
          # Body: { flag_type, severity?, message, evidence? }
          def create
            observation = ::Warehouse::ExtractedObservation.find(params[:extracted_observation_id])
            flag = observation.review_flags.create!(
              flag_type: params.fetch(:flag_type),
              severity:  params[:severity] || "medium",
              message:   params.fetch(:message),
              evidence:  params[:evidence]
            )
            observation.update!(needs_review: true) unless observation.needs_review
            render json: serialize(flag), status: :created
          rescue ActionController::ParameterMissing => e
            render json: { error: e.message }, status: :unprocessable_entity
          end

          # PATCH /api/v1/kpis/admin/extracted_observations/:extracted_observation_id/review_flags/:id
          # Body: { resolved_by, resolution_notes? }
          def update
            flag = ::Warehouse::ObservationReviewFlag
              .where(extracted_observation_id: params[:extracted_observation_id])
              .find(params[:id])
            flag.resolve!(
              resolved_by: params.fetch(:resolved_by),
              notes: params[:resolution_notes]
            )
            render json: serialize(flag), status: :ok
          rescue ActionController::ParameterMissing => e
            render json: { error: e.message }, status: :unprocessable_entity
          end

          private

          def serialize(f)
            {
              id: f.id,
              extracted_observation_id: f.extracted_observation_id,
              flag_type: f.flag_type,
              severity: f.severity,
              message: f.message,
              evidence: f.evidence,
              resolved_at: f.resolved_at,
              resolved_by: f.resolved_by,
              resolution_notes: f.resolution_notes,
              created_at: f.created_at
            }
          end
        end
      end
    end
  end
end
