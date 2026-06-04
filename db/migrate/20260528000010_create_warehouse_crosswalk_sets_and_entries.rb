class CreateWarehouseCrosswalkSetsAndEntries < ActiveRecord::Migration[8.1]
  WEIGHT_BASES = %w[
    area population dwellings households business_count employment road_length
    property_assessment manual exact_containment unknown
  ].freeze

  RELATIONSHIP_KINDS = %w[
    equivalent contains contained_by split merged overlaps allocated estimated manual
  ].freeze

  COMPATIBILITIES = %w[recommended acceptable risky not_allowed].freeze

  def up
    execute <<~SQL
      CREATE TABLE warehouse.geography_crosswalk_sets (
        id bigserial PRIMARY KEY,
        name varchar NOT NULL,
        description text,
        from_code_system varchar NOT NULL,
        to_code_system   varchar NOT NULL,
        from_geo_type    varchar,
        to_geo_type      varchar,
        method varchar NOT NULL,
        weight_basis varchar NOT NULL,
        expected_weight_sum numeric NOT NULL DEFAULT 1.0,
        allow_partial_coverage boolean NOT NULL DEFAULT false,
        source_id  bigint REFERENCES warehouse.sources(id),
        valid_from date,
        valid_to   date,
        notes text,
        created_at timestamp(6) NOT NULL,
        updated_at timestamp(6) NOT NULL,
        CONSTRAINT crosswalk_sets_weight_basis_check
          CHECK (weight_basis IN (#{WEIGHT_BASES.map { |s| "'#{s}'" }.join(',')})),
        CONSTRAINT crosswalk_sets_valid_range
          CHECK (valid_to IS NULL OR valid_from IS NULL OR valid_to >= valid_from)
      )
    SQL

    add_index "warehouse.geography_crosswalk_sets",
              [ :from_code_system, :to_code_system, :weight_basis ],
              name: "idx_crosswalk_sets_systems_basis"

    execute <<~SQL
      CREATE TABLE warehouse.geography_crosswalk_entries (
        id bigserial PRIMARY KEY,
        crosswalk_set_id bigint NOT NULL REFERENCES warehouse.geography_crosswalk_sets(id) ON DELETE CASCADE,
        from_geo_id      bigint NOT NULL REFERENCES warehouse.geo_boundaries(id) ON DELETE CASCADE,
        to_geo_id        bigint NOT NULL REFERENCES warehouse.geo_boundaries(id) ON DELETE CASCADE,
        weight numeric NOT NULL,
        weight_numerator   numeric,
        weight_denominator numeric,
        confidence numeric,
        relationship_type varchar NOT NULL,
        notes text,
        created_at timestamp(6) NOT NULL,
        updated_at timestamp(6) NOT NULL,
        CONSTRAINT crosswalk_entries_weight_range
          CHECK (weight >= 0 AND weight <= 1),
        CONSTRAINT crosswalk_entries_confidence_range
          CHECK (confidence IS NULL OR (confidence >= 0 AND confidence <= 1)),
        CONSTRAINT crosswalk_entries_relationship_kind_check
          CHECK (relationship_type IN (#{RELATIONSHIP_KINDS.map { |s| "'#{s}'" }.join(',')}))
      )
    SQL

    add_index "warehouse.geography_crosswalk_entries",
              [ :crosswalk_set_id, :from_geo_id, :to_geo_id ], unique: true,
              name: "idx_crosswalk_entries_unique"
    add_index "warehouse.geography_crosswalk_entries", :from_geo_id,
              name: "idx_crosswalk_entries_from"
    add_index "warehouse.geography_crosswalk_entries", :to_geo_id,
              name: "idx_crosswalk_entries_to"

    execute <<~SQL
      CREATE TABLE warehouse.crosswalk_metric_compatibility (
        id bigserial PRIMARY KEY,
        crosswalk_set_id bigint NOT NULL REFERENCES warehouse.geography_crosswalk_sets(id) ON DELETE CASCADE,
        measure_id       bigint NOT NULL REFERENCES warehouse.measures(id) ON DELETE CASCADE,
        compatibility varchar NOT NULL,
        reason text,
        created_at timestamp(6) NOT NULL,
        updated_at timestamp(6) NOT NULL,
        CONSTRAINT cmc_compatibility_check
          CHECK (compatibility IN (#{COMPATIBILITIES.map { |s| "'#{s}'" }.join(',')}))
      )
    SQL

    add_index "warehouse.crosswalk_metric_compatibility",
              [ :crosswalk_set_id, :measure_id ], unique: true,
              name: "idx_cmc_set_measure"

    execute <<~SQL
      CREATE VIEW warehouse.crosswalk_weight_checks AS
      SELECT
        crosswalk_set_id,
        from_geo_id,
        SUM(weight) AS total_weight,
        COUNT(*)    AS target_count
      FROM warehouse.geography_crosswalk_entries
      GROUP BY crosswalk_set_id, from_geo_id
    SQL

    # Backfill: one crosswalk_set per (source_type, target_type, census_year),
    # one entry per geo_crosswalks row (forward direction).
    execute <<~SQL
      INSERT INTO warehouse.geography_crosswalk_sets
        (name, from_code_system, to_code_system, from_geo_type, to_geo_type,
         method, weight_basis, expected_weight_sum, valid_from, created_at, updated_at)
      SELECT DISTINCT
        gc.source_type || ' to ' || gc.target_type || ' (' || COALESCE(gc.census_year::text, 'any') || ')',
        gc.source_type || '_' || COALESCE(gc.census_year::text, 'any'),
        gc.target_type || '_' || COALESCE(gc.census_year::text, 'any'),
        gc.source_type,
        gc.target_type,
        'tabular',
        'population',
        1.0,
        CASE WHEN gc.census_year IS NULL THEN NULL ELSE make_date(gc.census_year, 1, 1) END,
        now(), now()
      FROM warehouse.geo_crosswalks gc
    SQL

    execute <<~SQL
      INSERT INTO warehouse.geography_crosswalk_entries
        (crosswalk_set_id, from_geo_id, to_geo_id, weight, confidence,
         relationship_type, created_at, updated_at)
      SELECT
        s.id,
        gc.source_id,
        gc.target_id,
        COALESCE(gc.weight_source_to_target, 0)::numeric,
        1.0,
        CASE
          WHEN gc.weight_source_to_target IS NULL THEN 'overlaps'
          WHEN gc.weight_source_to_target >= 0.999 THEN 'contained_by'
          ELSE 'allocated'
        END,
        now(), now()
      FROM warehouse.geo_crosswalks gc
      JOIN warehouse.geography_crosswalk_sets s
        ON s.from_code_system = gc.source_type || '_' || COALESCE(gc.census_year::text, 'any')
       AND s.to_code_system   = gc.target_type || '_' || COALESCE(gc.census_year::text, 'any')
      ON CONFLICT (crosswalk_set_id, from_geo_id, to_geo_id) DO NOTHING
    SQL
  end

  def down
    execute "DROP VIEW IF EXISTS warehouse.crosswalk_weight_checks"
    drop_table "warehouse.crosswalk_metric_compatibility"
    drop_table "warehouse.geography_crosswalk_entries"
    drop_table "warehouse.geography_crosswalk_sets"
  end
end
