module Api
  module V1
    module Kpis
      class OrganizationsController < BaseController
        def index
          jurisdiction = ::Warehouse::Jurisdiction.find_by!(slug: params[:jurisdiction_slug])
          orgs = jurisdiction.organizations
            .order(:canonical_name)
            .includes(:predecessor_lineages, :successor_lineages)
          render json: { data: orgs.map { |o| serialize(o) } }
        end

        def show
          jurisdiction = ::Warehouse::Jurisdiction.find_by!(slug: params[:jurisdiction_slug])
          org = jurisdiction.organizations
            .includes(:predecessor_lineages, :successor_lineages)
            .find_by!(slug: params[:slug])
          render json: serialize(org, detail: true)
        end

        private

        def serialize(org, detail: false)
          base = {
            id: org.id,
            slug: org.slug,
            canonical_name: org.canonical_name,
            kind: org.kind,
            active_from_year: org.active_from_year,
            active_to_year: org.active_to_year,
            description: org.description,
            jurisdiction_id: org.jurisdiction_id
          }
          if detail
            base[:lineages] = {
              predecessors: org.predecessor_lineages.map { |l| serialize_lineage(l, :predecessor) },
              successors:   org.successor_lineages.map { |l| serialize_lineage(l, :successor) }
            }
          end
          base
        end

        def serialize_lineage(lineage, direction)
          other = direction == :predecessor ? lineage.predecessor : lineage.successor
          {
            other_organization: { id: other.id, slug: other.slug, canonical_name: other.canonical_name },
            transition_year: lineage.transition_year,
            transition_kind: lineage.transition_kind,
            acknowledged_in_document_id: lineage.acknowledged_in_document_id,
            notes: lineage.notes
          }
        end
      end
    end
  end
end
