module Api
  module V1
    module Kpis
      module Admin
        class OrganizationsController < BaseController
          # POST /api/v1/kpis/admin/organizations
          # Body: { organization: { jurisdiction_slug, slug, canonical_name,
          #                         kind?, description?, parent_organization_slug?,
          #                         active_from_year?, active_to_year?,
          #                         aliases?: [string,...], agent_run_id? } }
          #
          # Idempotent on (jurisdiction_id, slug). Aliases are upserted by alias_name.
          # Returns { id, slug, canonical_name, created } where `created` is true if
          # the row was newly inserted.
          def create
            attrs = params.require(:organization).permit(
              :jurisdiction_slug, :slug, :canonical_name, :kind, :description,
              :parent_organization_slug, :active_from_year, :active_to_year,
              :agent_run_id, aliases: []
            ).to_h.symbolize_keys

            jurisdiction = ::Warehouse::Jurisdiction.find_by!(slug: attrs.fetch(:jurisdiction_slug))
            parent = if (pslug = attrs[:parent_organization_slug])
              ::Warehouse::Organization.find_by(jurisdiction_id: jurisdiction.id, slug: pslug)
            end

            org = ::Warehouse::Organization.find_or_initialize_by(
              jurisdiction_id: jurisdiction.id,
              slug: attrs.fetch(:slug)
            )
            created = org.new_record?
            org.canonical_name = attrs.fetch(:canonical_name) if created || attrs[:canonical_name]
            org.kind = attrs[:kind] if attrs.key?(:kind)
            org.description = attrs[:description] if attrs.key?(:description)
            org.parent_organization_id = parent&.id if attrs.key?(:parent_organization_slug)
            org.active_from_year = attrs[:active_from_year] if attrs.key?(:active_from_year)
            org.active_to_year   = attrs[:active_to_year]   if attrs.key?(:active_to_year)
            org.save!

            Array(attrs[:aliases]).each do |alias_name|
              next if alias_name.blank?
              org.organization_aliases.find_or_create_by!(alias_name: alias_name)
            end
            # Also register the canonical name as an alias for future lookups.
            org.organization_aliases.find_or_create_by!(alias_name: org.canonical_name)

            render json: {
              id: org.id,
              slug: org.slug,
              canonical_name: org.canonical_name,
              jurisdiction_id: org.jurisdiction_id,
              created: created
            }, status: :ok
          end
        end
      end
    end
  end
end
