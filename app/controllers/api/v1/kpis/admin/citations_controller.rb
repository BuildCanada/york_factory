module Api
  module V1
    module Kpis
      module Admin
        class CitationsController < BaseController
          LEGACY_CITATION_FIELDS = {
            "page_number" => "source_page",
            "value_raw_text" => "value_raw"
          }.freeze

          # POST /api/v1/kpis/admin/citations
          # Body: { agent_run_id?: <int>, citations: [ {...}, {...} ] }
          #
          # Each citation is an extracted observation (agent claim, not yet a fact).
          # Required: measure_id, measurement_year, value_type, document_id.
          # Optional: period_basis (default 'full_year'), value_numeric / value_text,
          # value_raw, source_page, source_section, source_table, source_chart,
          # evidence_quote, period_start, period_end, period_type, unit_raw,
          # extraction_confidence (0..1), needs_review (bool),
          # period_label_raw, metric_version_id, composition_id, component_id,
          # *_raw labels (metric_name_raw, geography_name_raw, jurisdiction_name_raw,
          # reporting/responsible/observed_organization_raw), entity FKs
          # (reporting/responsible/observed_organization_id, geo_boundary_id,
          # jurisdiction_id), notes.
          # agent_run_id stamps every observation in the batch.
          def create
            agent_run_id = params[:agent_run_id].presence

            legacy_fields = legacy_fields_in_payload
            if legacy_fields.any?
              return render json: {
                error: "unsupported_citation_fields",
                fields: legacy_fields,
                replacements: legacy_fields.index_with { |field| LEGACY_CITATION_FIELDS[field] }
              }, status: :unprocessable_entity
            end

            rows = Array(params.permit(citations: %i[
              measure_id measurement_year value_type period_basis
              period_start period_end period_type
              value_numeric value_text value_raw unit_raw
              document_id source_page source_section source_table source_chart
              evidence_quote extraction_confidence needs_review
              period_label_raw metric_version_id composition_id component_id
              metric_name_raw geography_name_raw jurisdiction_name_raw
              reporting_organization_raw responsible_organization_raw observed_organization_raw
              reporting_organization_id responsible_organization_id observed_organization_id
              geo_boundary_id jurisdiction_id notes
            ]).to_h[:citations] || []).map(&:symbolize_keys)

            return render json: { error: "no_citations" }, status: :unprocessable_entity if rows.empty?

            now = Time.current
            payload = rows.map do |r|
              {
                measure_id: r.fetch(:measure_id),
                measurement_year: r.fetch(:measurement_year),
                value_type: r.fetch(:value_type),
                period_basis: r[:period_basis] || "full_year",
                period_start: r[:period_start],
                period_end: r[:period_end],
                period_type: r[:period_type],
                period_label_raw: r[:period_label_raw],
                value_numeric: r[:value_numeric],
                value_text: r[:value_text],
                value_raw: r[:value_raw],
                unit_raw: r[:unit_raw],
                metric_version_id: r[:metric_version_id],
                composition_id: r[:composition_id],
                component_id: r[:component_id],
                document_id: r.fetch(:document_id),
                source_page: r[:source_page],
                source_section: r[:source_section],
                source_table: r[:source_table],
                source_chart: r[:source_chart],
                evidence_quote: r[:evidence_quote],
                extraction_confidence: r[:extraction_confidence],
                needs_review: r.key?(:needs_review) ? r[:needs_review] : false,
                review_status: "pending",
                metric_name_raw: r[:metric_name_raw],
                geography_name_raw: r[:geography_name_raw],
                jurisdiction_name_raw: r[:jurisdiction_name_raw],
                reporting_organization_raw: r[:reporting_organization_raw],
                responsible_organization_raw: r[:responsible_organization_raw],
                observed_organization_raw: r[:observed_organization_raw],
                reporting_organization_id: r[:reporting_organization_id],
                responsible_organization_id: r[:responsible_organization_id],
                observed_organization_id: r[:observed_organization_id],
                geo_boundary_id: r[:geo_boundary_id],
                jurisdiction_id: r[:jurisdiction_id],
                notes: r[:notes],
                agent_run_id: agent_run_id,
                created_at: now,
                updated_at: now
              }
            end

            result = ::Warehouse::ExtractedObservation.insert_all(
              payload,
              unique_by: :idx_extracted_observations_unique,
              returning: %w[id]
            )
            inserted_ids = result.rows.flatten
            render json: {
              inserted: inserted_ids.length,
              skipped_duplicate: payload.length - inserted_ids.length,
              ids: inserted_ids
            }, status: :ok
          rescue KeyError => e
            render json: { error: "invalid_citation", details: e.message }, status: :unprocessable_entity
          end

          private

          def legacy_fields_in_payload
            Array(params[:citations]).flat_map do |row|
              row.respond_to?(:keys) ? row.keys.map(&:to_s) : []
            end.intersection(LEGACY_CITATION_FIELDS.keys)
          end
        end
      end
    end
  end
end
