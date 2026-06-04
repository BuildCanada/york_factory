module Api
  module V1
    module Kpis
      module Admin
        class ObservationFootnotesController < BaseController
          # POST   /api/v1/kpis/admin/extracted_observations/:extracted_observation_id/footnote_links
          # DELETE /api/v1/kpis/admin/extracted_observations/:extracted_observation_id/footnote_links/:id
          def create
            observation = ::Warehouse::ExtractedObservation.find(params[:extracted_observation_id])
            footnote = ::Warehouse::SourceFootnote.find(params.fetch(:source_footnote_id))

            unless footnote.document_id == observation.document_id
              return render json: { error: "footnote_document_mismatch" }, status: :unprocessable_entity
            end

            ::Warehouse::ObservationFootnote.find_or_create_by!(
              extracted_observation_id: observation.id,
              source_footnote_id:       footnote.id
            )
            render json: { extracted_observation_id: observation.id, source_footnote_id: footnote.id },
                   status: :created
          rescue ActionController::ParameterMissing => e
            render json: { error: e.message }, status: :unprocessable_entity
          end

          def destroy
            ::Warehouse::ObservationFootnote.where(
              extracted_observation_id: params[:extracted_observation_id],
              source_footnote_id:       params[:id]
            ).delete_all
            head :no_content
          end
        end
      end
    end
  end
end
