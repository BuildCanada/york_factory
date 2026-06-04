module Api
  module V1
    module Kpis
      class OrganizationLineagesController < BaseController
        def index
          scope = ::Warehouse::OrganizationLineage.includes(:predecessor, :successor)

          if params[:predecessor_slug].present?
            org = resolve_organization_by_slug!(
              params[:predecessor_slug],
              jurisdiction_slug: params[:jurisdiction_slug]
            )
            scope = scope.where(predecessor_id: org.id)
          end

          if params[:successor_slug].present?
            org = resolve_organization_by_slug!(
              params[:successor_slug],
              jurisdiction_slug: params[:jurisdiction_slug]
            )
            scope = scope.where(successor_id: org.id)
          end

          if params[:jurisdiction_slug].present?
            jur = ::Warehouse::Jurisdiction.find_by!(slug: params[:jurisdiction_slug])
            org_ids = ::Warehouse::Organization.where(jurisdiction_id: jur.id).pluck(:id)
            scope = scope.where(predecessor_id: org_ids).or(scope.where(successor_id: org_ids))
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
            predecessor: { id: l.predecessor.id, slug: l.predecessor.slug, canonical_name: l.predecessor.canonical_name },
            successor:   { id: l.successor.id,   slug: l.successor.slug,   canonical_name: l.successor.canonical_name }
          }
        end
      end
    end
  end
end
