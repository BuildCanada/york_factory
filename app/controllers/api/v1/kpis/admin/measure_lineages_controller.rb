module Api
  module V1
    module Kpis
      module Admin
        class MeasureLineagesController < BaseController
          def create
            attrs = params.require(:lineage).permit(
              :predecessor_id, :successor_id, :transition_year,
              :transition_kind, :acknowledged_in_document_id, :notes
            ).to_h.symbolize_keys

            lineage = ::Warehouse::MeasureLineage.find_or_initialize_by(
              predecessor_id: attrs.fetch(:predecessor_id),
              successor_id: attrs.fetch(:successor_id),
              transition_year: attrs.fetch(:transition_year),
              transition_kind: attrs.fetch(:transition_kind)
            )
            lineage.acknowledged_in_document_id = attrs[:acknowledged_in_document_id]
            lineage.notes = attrs[:notes]
            lineage.save!

            render json: { id: lineage.id }, status: :ok
          end
        end
      end
    end
  end
end
