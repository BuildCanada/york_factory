module Api
  module V1
    module Kpis
      module Admin
        class OrganizationLineagesController < BaseController
          def create
            attrs = params.require(:lineage).permit(
              :predecessor_slug, :successor_slug, :transition_year,
              :transition_kind, :acknowledged_in_document_id, :notes
            ).to_h.symbolize_keys

            pred = ::Warehouse::Organization.find_by!(slug: attrs.fetch(:predecessor_slug))
            succ = ::Warehouse::Organization.find_by!(slug: attrs.fetch(:successor_slug))

            lineage = ::Warehouse::OrganizationLineage.find_or_initialize_by(
              predecessor_id: pred.id,
              successor_id: succ.id,
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
