module Api
  module V1
    module Kpis
      module Admin
        class ExtractedObservationsController < BaseController
          # POST /api/v1/kpis/admin/extracted_observations/:id/approve
          # Body: { reviewer: "alice", notes?, new_value?: { ... }, status?, vintage_date? }
          def approve
            observation = ::Warehouse::ExtractedObservation.find(params[:id])
            reviewer = params.fetch(:reviewer)
            new_value = params[:new_value].present? ? params.require(:new_value).permit!.to_h : nil
            vintage_date = params[:vintage_date].present? ? Date.parse(params[:vintage_date]) : nil

            observation.approve!(
              reviewer: reviewer,
              notes: params[:notes],
              new_value: new_value,
              status: params[:status] || "reported",
              vintage_date: vintage_date,
              is_total:    ActiveModel::Type::Boolean.new.cast(params[:is_total]) || false,
              is_residual: ActiveModel::Type::Boolean.new.cast(params[:is_residual]) || false
            )
            render json: serialize(observation.reload), status: :ok
          rescue ActionController::ParameterMissing => e
            render json: { error: e.message }, status: :unprocessable_entity
          end

          # POST /api/v1/kpis/admin/extracted_observations/:id/reject
          # Body: { reviewer: "alice", notes? }
          def reject
            observation = ::Warehouse::ExtractedObservation.find(params[:id])
            observation.reject!(reviewer: params.fetch(:reviewer), notes: params[:notes])
            render json: serialize(observation.reload), status: :ok
          rescue ActionController::ParameterMissing => e
            render json: { error: e.message }, status: :unprocessable_entity
          end

          private

          def serialize(o)
            {
              id: o.id,
              review_status: o.review_status,
              needs_review: o.needs_review,
              canonical_observation_id: o.canonical_observation&.id,
              open_flag_count: o.open_review_flags.count,
              decisions: o.review_decisions.order(:created_at).map { |d|
                { id: d.id, reviewer: d.reviewer, decision: d.decision, notes: d.notes,
                  created_at: d.created_at }
              }
            }
          end
        end
      end
    end
  end
end
