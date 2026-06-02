module Api
  module V1
    module Kpis
      class ObservationsController < BaseController
        # GET /api/v1/kpis/observations
        # Returns canonical (approved) observations. Filters per spec §14:
        # measure_id, measure_category, composition_id, component_id,
        # observed_organization_slug, reporting_organization_slug,
        # jurisdiction_slug, geo_boundary_id, year, value_type,
        # period_basis, status, is_total.
        def index
          scope = ::Warehouse::CanonicalObservation
            .joins(:measure)
            .includes(:measure, :document)

          scope = scope.where(measure_id: params[:measure_id])             if params[:measure_id].present?
          scope = scope.where("warehouse.measures.category" => params[:measure_category]) if params[:measure_category].present?
          scope = scope.where(composition_id: params[:composition_id])     if params[:composition_id].present?
          scope = scope.where(component_id: params[:component_id])         if params[:component_id].present?
          scope = scope.where(measurement_year: params[:year])             if params[:year].present?
          scope = scope.where(value_type: params[:value_type])             if params[:value_type].present?
          scope = scope.where(period_basis: params[:period_basis])         if params[:period_basis].present?
          scope = scope.where(status: params[:status])                     if params[:status].present?
          scope = scope.where(geo_boundary_id: params[:geo_boundary_id])   if params[:geo_boundary_id].present?
          scope = scope.where(is_total: ActiveModel::Type::Boolean.new.cast(params[:is_total])) if params.key?(:is_total)

          if params[:observed_organization_slug].present?
            org = resolve_organization_by_slug!(
              params[:observed_organization_slug],
              jurisdiction_slug: params[:jurisdiction_slug]
            )
            scope = scope.where(observed_organization_id: org.id)
          end
          if params[:reporting_organization_slug].present?
            org = resolve_organization_by_slug!(params[:reporting_organization_slug])
            scope = scope.where(reporting_organization_id: org.id)
          end
          if params[:jurisdiction_slug].present?
            jur = ::Warehouse::Jurisdiction.find_by!(slug: params[:jurisdiction_slug])
            scope = scope.where(jurisdiction_id: jur.id)
          end

          scope = scope.order(measurement_year: :desc, approved_at: :desc, id: :desc)
          pagy, rows = pagy(scope, limit: (params[:per_page] || 100).to_i)
          render json: { data: rows.map { |r| serialize(r) }, meta: pagy_metadata(pagy) }
        end

        # GET /api/v1/kpis/observations/:id
        def show
          obs = ::Warehouse::CanonicalObservation
            .includes(:measure, :document, :extracted_observation)
            .find(params[:id])
          render json: serialize(obs).merge(
            derivation_count: ::Warehouse::DerivedObservation
              .where(from_canonical_observation_id: obs.id).count,
            extracted_observation_id: obs.extracted_observation_id
          )
        end

        # GET /api/v1/kpis/observations/:id/derivations
        def derivations
          obs = ::Warehouse::CanonicalObservation.find(params[:id])
          rows = ::Warehouse::DerivedObservation
            .where(from_canonical_observation_id: obs.id)
            .includes(:crosswalk_set, :derived_geo)
            .order(created_at: :desc)
          render json: { data: rows.map { |d| serialize_derived(d) } }
        end

        private

        def serialize(c)
          {
            id: c.id,
            measure_id: c.measure_id,
            measure_slug: c.measure&.slug,
            measure_name: c.measure&.canonical_name,
            metric_version_id: c.metric_version_id,
            composition_id: c.composition_id,
            component_id: c.component_id,
            measurement_year: c.measurement_year,
            period_start: c.period_start,
            period_end: c.period_end,
            period_type: c.period_type,
            value_type: c.value_type,
            period_basis: c.period_basis,
            value_numeric: c.value_numeric,
            value_text: c.value_text,
            unit_id: c.unit_id,
            status: c.status,
            vintage_date: c.vintage_date,
            is_total: c.is_total,
            is_residual: c.is_residual,
            observed_organization_id: c.observed_organization_id,
            responsible_organization_id: c.responsible_organization_id,
            reporting_organization_id: c.reporting_organization_id,
            jurisdiction_id: c.jurisdiction_id,
            geo_boundary_id: c.geo_boundary_id,
            document: c.document && {
              id: c.document.id,
              doc_url: c.document.doc_url,
              doc_title: c.document.doc_title,
              fiscal_year: c.document.fiscal_year,
              published_at: c.document.published_at
            },
            approved_at: c.approved_at,
            approved_by: c.approved_by
          }
        end

        def serialize_derived(d)
          {
            id: d.id,
            measure_id: d.measure_id,
            from_canonical_observation_id: d.from_canonical_observation_id,
            crosswalk_set_id: d.crosswalk_set_id,
            crosswalk_set_name: d.crosswalk_set&.name,
            original_geo_id: d.original_geo_id,
            derived_geo_id: d.derived_geo_id,
            measurement_year: d.measurement_year,
            value_numeric: d.value_numeric,
            unit_id: d.unit_id,
            derivation_method: d.derivation_method,
            confidence: d.confidence,
            notes: d.notes,
            created_at: d.created_at
          }
        end
      end
    end
  end
end
