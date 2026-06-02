module Api
  module V1
    module Kpis
      class MeasuresController < BaseController
        def index
          scope = ::Warehouse::Measure.includes(:unit, :organization)

          if params[:jurisdiction_slug].present?
            jurisdiction = ::Warehouse::Jurisdiction.find_by!(slug: params[:jurisdiction_slug])
            org_ids = jurisdiction.organizations.pluck(:id)
            scope = scope.where(organization_id: org_ids)
          end

          if params[:organization_slug].present?
            org = resolve_organization_by_slug!(
              params[:organization_slug],
              jurisdiction_slug: params[:jurisdiction_slug]
            )
            scope = scope.where(organization_id: org.id)
          end

          scope = scope.order(:canonical_name)
          pagy, measures = pagy(scope, limit: (params[:per_page] || 50).to_i)

          render json: {
            data: measures.map { |m| serialize(m) },
            meta: pagy_metadata(pagy)
          }
        end

        def show
          measure = ::Warehouse::Measure
            .includes(:unit, :organization, :predecessor_lineages, :successor_lineages)
            .find(params[:id])
          render json: serialize(measure, detail: true)
        end

        private

        def serialize(measure, detail: false)
          base = {
            id: measure.id,
            slug: measure.slug,
            canonical_name: measure.canonical_name,
            organization: measure.organization && serialize_organization_summary(measure.organization),
            unit: serialize_unit(measure.unit),
            service_category: measure.service_category,
            first_seen_year: measure.first_seen_year,
            last_seen_year: measure.last_seen_year
          }
          if detail
            base[:description] = measure.description
            base[:lineages] = {
              predecessors: measure.predecessor_lineages.map { |l| serialize_lineage(l) },
              successors:   measure.successor_lineages.map { |l| serialize_lineage(l) }
            }
          end
          base
        end

        def serialize_lineage(lineage)
          {
            predecessor_id: lineage.predecessor_id,
            successor_id: lineage.successor_id,
            transition_year: lineage.transition_year,
            transition_kind: lineage.transition_kind,
            notes: lineage.notes
          }
        end
      end
    end
  end
end
