module Api
  module V1
    module Kpis
      module Admin
        class CitationsController < BaseController
          # POST /api/v1/kpis/admin/citations
          # Body: { agent_run_id?: <int>, citations: [ {...}, {...} ] }
          # Each citation must include measure_id, measurement_year, value_type,
          # document_id, period_basis (optional, defaults to 'full_year'),
          # value_numeric / value_text, value_raw_text (optional), page_number (optional),
          # notes (optional). agent_run_id stamps every citation in the batch.
          def create
            agent_run_id = params[:agent_run_id].presence

            rows = Array(params.permit(citations: %i[
              measure_id measurement_year value_type period_basis
              value_numeric value_text value_raw_text
              document_id page_number notes
            ]).to_h[:citations] || []).map(&:symbolize_keys)

            return render json: { error: "no_citations" }, status: :unprocessable_entity if rows.empty?

            now = Time.current
            payload = rows.map do |r|
              {
                measure_id: r.fetch(:measure_id),
                measurement_year: r.fetch(:measurement_year),
                value_type: r.fetch(:value_type),
                period_basis: r[:period_basis] || "full_year",
                value_numeric: r[:value_numeric],
                value_text: r[:value_text],
                value_raw_text: r[:value_raw_text],
                document_id: r.fetch(:document_id),
                page_number: r[:page_number],
                notes: r[:notes],
                agent_run_id: agent_run_id,
                created_at: now,
                updated_at: now
              }
            end

            result = ::Warehouse::MeasureCitation.insert_all(
              payload,
              unique_by: :idx_measure_citations_unique,
              returning: %w[id]
            )
            inserted_ids = result.rows.flatten
            render json: {
              inserted: inserted_ids.length,
              skipped_duplicate: payload.length - inserted_ids.length,
              ids: inserted_ids
            }, status: :ok
          end
        end
      end
    end
  end
end
