class AddJurisdictionToObservationUniqueness < ActiveRecord::Migration[8.1]
  # Cross-country series store one row per country under the same measure,
  # differentiated only by jurisdiction_id — which the unique index and the
  # measure_facts dedupe window didn't include (all prior data was
  # single-jurisdiction via organizations, so jurisdiction_id was always NULL).
  #
  # NULLS NOT DISTINCT (so rows with NULL dimension columns still collide)
  # requires Postgres 15+.
  TABLE = "warehouse.extracted_observations"
  INDEX_NAME = "idx_extracted_observations_unique"

  COLUMNS_WITH_JURISDICTION = %i[
    measure_id measurement_year value_type period_basis document_id
    composition_id component_id observed_organization_id geo_boundary_id
    jurisdiction_id
  ].freeze
  COLUMNS_WITHOUT_JURISDICTION = COLUMNS_WITH_JURISDICTION - %i[jurisdiction_id]

  def up
    remove_index TABLE, name: INDEX_NAME
    add_index TABLE, COLUMNS_WITH_JURISDICTION,
      unique: true, nulls_not_distinct: true, name: INDEX_NAME

    execute <<~SQL
      CREATE OR REPLACE VIEW warehouse.measure_facts AS
       SELECT id AS canonical_observation_id,
          measure_id,
          measurement_year,
          value_type,
          period_basis,
          value_numeric,
          value_text,
          document_id,
          extracted_observation_id,
          observed_organization_id,
          geo_boundary_id,
          jurisdiction_id,
          status,
          vintage_date,
          approved_at
         FROM ( SELECT c.id,
                  c.extracted_observation_id,
                  c.measure_id,
                  c.document_id,
                  c.observed_organization_id,
                  c.geo_boundary_id,
                  c.jurisdiction_id,
                  c.measurement_year,
                  c.value_type,
                  c.period_basis,
                  c.value_numeric,
                  c.value_text,
                  c.vintage_date,
                  c.status,
                  c.approved_at,
                  row_number() OVER (
                    PARTITION BY c.measure_id, c.measurement_year, c.value_type, c.period_basis,
                                 c.observed_organization_id, c.geo_boundary_id, c.jurisdiction_id
                    ORDER BY c.vintage_date DESC NULLS LAST, c.approved_at DESC, c.id DESC
                  ) AS rn
                 FROM warehouse.canonical_observations c) co
        WHERE (rn = 1)
    SQL
  end

  def down
    remove_index TABLE, name: INDEX_NAME
    add_index TABLE, COLUMNS_WITHOUT_JURISDICTION,
      unique: true, nulls_not_distinct: true, name: INDEX_NAME

    execute <<~SQL
      CREATE OR REPLACE VIEW warehouse.measure_facts AS
       SELECT id AS canonical_observation_id,
          measure_id,
          measurement_year,
          value_type,
          period_basis,
          value_numeric,
          value_text,
          document_id,
          extracted_observation_id,
          observed_organization_id,
          geo_boundary_id,
          jurisdiction_id,
          status,
          vintage_date,
          approved_at
         FROM ( SELECT c.id,
                  c.extracted_observation_id,
                  c.measure_id,
                  c.document_id,
                  c.observed_organization_id,
                  c.geo_boundary_id,
                  c.jurisdiction_id,
                  c.measurement_year,
                  c.value_type,
                  c.period_basis,
                  c.value_numeric,
                  c.value_text,
                  c.vintage_date,
                  c.status,
                  c.approved_at,
                  row_number() OVER (
                    PARTITION BY c.measure_id, c.measurement_year, c.value_type, c.period_basis,
                                 c.observed_organization_id, c.geo_boundary_id
                    ORDER BY c.vintage_date DESC NULLS LAST, c.approved_at DESC, c.id DESC
                  ) AS rn
                 FROM warehouse.canonical_observations c) co
        WHERE (rn = 1)
    SQL
  end
end
