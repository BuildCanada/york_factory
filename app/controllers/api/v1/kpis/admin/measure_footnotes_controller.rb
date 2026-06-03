module Api
  module V1
    module Kpis
      module Admin
        class MeasureFootnotesController < BaseController
          # POST   /api/v1/kpis/admin/measures/:measure_id/footnote_links
          # DELETE /api/v1/kpis/admin/measures/:measure_id/footnote_links/:id
          #
          # Measure-level footnote links carry context that has no observation
          # to live on — e.g. a footnote explaining why an indicator has no
          # data (retired, baseline pending, survey discontinued).
          def create
            measure = ::Warehouse::Measure.find(params[:measure_id])
            footnote = ::Warehouse::SourceFootnote.find(params.fetch(:source_footnote_id))

            ::Warehouse::MeasureFootnote.find_or_create_by!(
              measure_id:         measure.id,
              source_footnote_id: footnote.id
            )
            render json: { measure_id: measure.id, source_footnote_id: footnote.id },
                   status: :created
          rescue ActionController::ParameterMissing => e
            render json: { error: e.message }, status: :unprocessable_entity
          end

          def destroy
            ::Warehouse::MeasureFootnote.where(
              measure_id:         params[:measure_id],
              source_footnote_id: params[:id]
            ).delete_all
            head :no_content
          end
        end
      end
    end
  end
end
