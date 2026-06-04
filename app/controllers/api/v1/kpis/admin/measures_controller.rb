module Api
  module V1
    module Kpis
      module Admin
        class MeasuresController < BaseController
          def create
            attrs = measure_params

            unit = ::Warehouse::Unit.find_by(symbol: attrs.delete(:unit_symbol))
            return render json: { error: "unknown_unit", hint: "Add the unit symbol to db/seeds/kpis/units.yml and reseed" }, status: :unprocessable_entity if unit.nil?

            jurisdiction_slug = attrs.delete(:jurisdiction_slug)
            organization = if (slug = attrs.delete(:organization_slug))
              resolve_organization_by_slug!(slug, jurisdiction_slug: jurisdiction_slug)
            end

            measure = ::Warehouse::Measure.find_or_initialize_by(
              organization_id: organization&.id,
              slug: attrs.fetch(:slug)
            )
            measure.assign_attributes(
              canonical_name: attrs.fetch(:canonical_name),
              unit_id: unit.id,
              service_category: attrs[:service_category],
              description: attrs[:description],
              first_seen_year: attrs[:first_seen_year],
              last_seen_year: attrs[:last_seen_year],
              agent_run_id: attrs[:agent_run_id]
            )
            measure.save!

            render json: serialize(measure), status: :ok
          end

          private

          def measure_params
            params.require(:measure).permit(
              :jurisdiction_slug, :organization_slug, :slug, :canonical_name, :unit_symbol,
              :service_category, :description, :first_seen_year, :last_seen_year,
              :agent_run_id
            ).to_h.symbolize_keys
          end

          def serialize(measure)
            {
              id: measure.id,
              slug: measure.slug,
              canonical_name: measure.canonical_name,
              organization_id: measure.organization_id,
              unit_id: measure.unit_id
            }
          end
        end
      end
    end
  end
end
