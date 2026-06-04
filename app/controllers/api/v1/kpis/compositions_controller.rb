module Api
  module V1
    module Kpis
      class CompositionsController < BaseController
        # GET /api/v1/kpis/compositions
        # GET /api/v1/kpis/measures/:measure_id/compositions
        #
        # Lets ingestion agents discover existing metric compositions and
        # components before deciding whether to attach composition_id/component_id
        # to extracted observations.
        def index
          scope = ::Warehouse::MetricComposition
            .includes(:expected_total_unit, :components, measure: :organization)

          scope = scope.where(measure_id: params[:measure_id]) if params[:measure_id].present?

          if params[:organization_slug].present?
            org = resolve_organization_by_slug!(
              params[:organization_slug],
              jurisdiction_slug: params[:jurisdiction_slug]
            )
            scope = scope.where(measure_id: ::Warehouse::Measure.where(organization_id: org.id).select(:id))
          elsif params[:jurisdiction_slug].present?
            jur = ::Warehouse::Jurisdiction.find_by!(slug: params[:jurisdiction_slug])
            org_ids = ::Warehouse::Organization.where(jurisdiction_id: jur.id).select(:id)
            scope = scope.where(measure_id: ::Warehouse::Measure.where(organization_id: org_ids).select(:id))
          end

          scope = scope.where(composition_type: params[:composition_type]) if params[:composition_type].present?
          scope = scope.order(:measure_id, :composition_type, :name)

          pagy, compositions = pagy(scope, limit: (params[:per_page] || 100).to_i)
          render json: {
            data: compositions.map { |composition| serialize(composition) },
            meta: pagy_metadata(pagy)
          }
        end

        private

        def serialize(composition)
          {
            id: composition.id,
            measure: serialize_measure(composition.measure),
            composition_type: composition.composition_type,
            name: composition.name,
            expected_total: composition.expected_total,
            expected_total_unit: composition.expected_total_unit && serialize_unit(composition.expected_total_unit),
            allow_other: composition.allow_other,
            allow_unknown: composition.allow_unknown,
            notes: composition.notes,
            components: sorted_components(composition).map { |component| serialize_component(component) }
          }
        end

        def serialize_measure(measure)
          {
            id: measure.id,
            slug: measure.slug,
            canonical_name: measure.canonical_name,
            organization: measure.organization && serialize_organization_summary(measure.organization)
          }
        end

        def serialize_component(component)
          {
            id: component.id,
            measure_id: component.measure_id,
            composition_id: component.composition_id,
            component_type: component.component_type,
            component_code: component.component_code,
            component_name: component.component_name,
            parent_component_id: component.parent_component_id,
            valid_from: component.valid_from,
            valid_to: component.valid_to,
            sort_order: component.sort_order,
            notes: component.notes
          }
        end

        def sorted_components(composition)
          composition.components.sort_by do |component|
            [ component.sort_order || 1_000_000, component.component_code.to_s, component.component_name.to_s ]
          end
        end
      end
    end
  end
end
