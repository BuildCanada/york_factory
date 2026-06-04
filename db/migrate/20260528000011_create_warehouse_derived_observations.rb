class CreateWarehouseDerivedObservations < ActiveRecord::Migration[8.1]
  DERIVATION_METHODS = %w[
    crosswalk_allocation aggregation ratio_recompute definition_normalization rebase manual
  ].freeze

  def up
    execute <<~SQL
      CREATE TABLE warehouse.derived_observations (
        id bigserial PRIMARY KEY,
        measure_id bigint NOT NULL REFERENCES warehouse.measures(id) ON DELETE CASCADE,

        from_canonical_observation_id bigint REFERENCES warehouse.canonical_observations(id) ON DELETE SET NULL,
        crosswalk_set_id bigint REFERENCES warehouse.geography_crosswalk_sets(id) ON DELETE SET NULL,

        original_geo_id bigint REFERENCES warehouse.geo_boundaries(id),
        derived_geo_id  bigint REFERENCES warehouse.geo_boundaries(id),

        measurement_year integer NOT NULL,
        period_start date,
        period_end   date,
        period_type  varchar,

        value_numeric double precision,
        value_text    text,
        unit_id       bigint REFERENCES warehouse.units(id),

        derivation_method varchar NOT NULL,
        confidence numeric,
        notes text,

        created_at timestamp(6) NOT NULL,
        updated_at timestamp(6) NOT NULL,

        CONSTRAINT derived_observations_method_check
          CHECK (derivation_method IN (#{DERIVATION_METHODS.map { |s| "'#{s}'" }.join(',')})),
        CONSTRAINT derived_observations_confidence_range
          CHECK (confidence IS NULL OR (confidence >= 0 AND confidence <= 1))
      )
    SQL

    add_index "warehouse.derived_observations", :measure_id,
              name: "idx_derived_observations_measure"
    add_index "warehouse.derived_observations", :from_canonical_observation_id,
              name: "idx_derived_observations_source"
    add_index "warehouse.derived_observations", :crosswalk_set_id,
              name: "idx_derived_observations_crosswalk_set"
    add_index "warehouse.derived_observations", [ :measure_id, :derived_geo_id, :measurement_year ],
              name: "idx_derived_observations_lookup"
  end

  def down
    drop_table "warehouse.derived_observations"
  end
end
