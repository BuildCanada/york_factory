module Api
  module V1
    module Kpis
      class MeasureLineagesController < BaseController
        def index
          scope = ::Warehouse::MeasureLineage.includes(predecessor: :organization, successor: :organization)

          if params[:predecessor_id].present?
            scope = scope.where(predecessor_id: params[:predecessor_id])
          end

          if params[:successor_id].present?
            scope = scope.where(successor_id: params[:successor_id])
          end

          if params[:organization_slug].present?
            org = ::Warehouse::Organization.find_by!(slug: params[:organization_slug])
            measure_ids = ::Warehouse::Measure.where(organization_id: org.id).pluck(:id)
            scope = scope.where(predecessor_id: measure_ids).or(scope.where(successor_id: measure_ids))
          end

          scope = scope.where(transition_year: params[:transition_year]) if params[:transition_year].present?
          scope = scope.where(transition_kind: params[:transition_kind]) if params[:transition_kind].present?

          scope = scope.order(transition_year: :desc, id: :desc)
          pagy, lineages = pagy(scope, limit: (params[:per_page] || 50).to_i)

          render json: {
            data: lineages.map { |l| serialize(l) },
            meta: pagy_metadata(pagy)
          }
        end

        private

        def serialize(l)
          {
            id: l.id,
            transition_year: l.transition_year,
            transition_kind: l.transition_kind,
            notes: l.notes,
            acknowledged_in_document_id: l.acknowledged_in_document_id,
            predecessor: serialize_measure_ref(l.predecessor),
            successor:   serialize_measure_ref(l.successor)
          }
        end

        def serialize_measure_ref(m)
          {
            id: m.id,
            slug: m.slug,
            canonical_name: m.canonical_name,
            organization_slug: m.organization&.slug
          }
        end
      end
    end
  end
end
