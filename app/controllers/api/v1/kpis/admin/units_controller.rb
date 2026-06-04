module Api
  module V1
    module Kpis
      module Admin
        class UnitsController < BaseController
          # POST /api/v1/kpis/admin/units
          # Body: { unit: { symbol, kind, base_unit?, scale?, currency_code?,
          #                 denominator_unit?, denominator_scale?, notes? } }
          def create
            attrs = unit_params

            # Prefer pre-existing units: an existing symbol is returned as-is,
            # never overwritten by agent input.
            if (existing = ::Warehouse::Unit.find_by(symbol: attrs.fetch(:symbol)))
              return render json: serialize_unit(existing).merge(notes: existing.notes, existing: true), status: :ok
            end

            unit = ::Warehouse::Unit.create!(
              symbol: attrs.fetch(:symbol),
              kind: attrs.fetch(:kind),
              base_unit: attrs[:base_unit],
              scale: attrs[:scale] || 1.0,
              currency_code: attrs[:currency_code],
              denominator_unit: attrs[:denominator_unit],
              denominator_scale: attrs[:denominator_scale],
              notes: attrs[:notes]
            )

            render json: serialize_unit(unit).merge(notes: unit.notes, existing: false), status: :created
          end

          private

          def serialize_unit(unit)
            {
              id: unit.id,
              symbol: unit.symbol,
              kind: unit.kind,
              base_unit: unit.base_unit,
              scale: unit.scale,
              currency_code: unit.currency_code,
              denominator_unit: unit.denominator_unit,
              denominator_scale: unit.denominator_scale
            }
          end

          def unit_params
            params.require(:unit).permit(
              :symbol, :kind, :base_unit, :scale, :currency_code,
              :denominator_unit, :denominator_scale, :notes
            ).to_h.symbolize_keys
          end
        end
      end
    end
  end
end
