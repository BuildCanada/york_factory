class AddPeriodStartToObservationUniqueness < ActiveRecord::Migration[8.1]
  # Monthly series (StatCan CPI) store twelve rows per (measure, year,
  # jurisdiction), differentiated only by period_start — which the unique
  # index and the measure_facts dedupe window didn't include (all prior
  # economy data was annual, one row per year). Adds a "month" period_basis,
  # includes period_start in the uniqueness key, and exposes the period
  # columns in measure_facts so the series API can serve month-level points.
  PERIOD_BASES_WITH_MONTH = %w[full_year ytd_q1 ytd_q2 ytd_q3 as_of_date month].freeze
  PERIOD_BASES_WITHOUT_MONTH = %w[full_year ytd_q1 ytd_q2 ytd_q3 as_of_date].freeze

  def up
    replace_period_basis_checks(PERIOD_BASES_WITH_MONTH)

    execute "DROP INDEX IF EXISTS warehouse.idx_extracted_observations_unique"
    execute <<~SQL
      CREATE UNIQUE INDEX idx_extracted_observations_unique
        ON warehouse.extracted_observations (
          measure_id, measurement_year, value_type, period_basis, period_start,
          document_id, composition_id, component_id, observed_organization_id,
          geo_boundary_id, jurisdiction_id
        ) NULLS NOT DISTINCT
    SQL

    execute "DROP VIEW warehouse.measure_facts"
    execute <<~SQL
      CREATE VIEW warehouse.measure_facts AS
       SELECT id AS canonical_observation_id,
          measure_id,
          measurement_year,
          value_type,
          period_basis,
          period_start,
          period_end,
          period_type,
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
                  c.period_start,
                  c.period_end,
                  c.period_type,
                  c.value_numeric,
                  c.value_text,
                  c.vintage_date,
                  c.status,
                  c.approved_at,
                  row_number() OVER (
                    PARTITION BY c.measure_id, c.measurement_year, c.value_type, c.period_basis,
                                 c.period_start, c.observed_organization_id, c.geo_boundary_id,
                                 c.jurisdiction_id
                    ORDER BY c.vintage_date DESC NULLS LAST, c.approved_at DESC, c.id DESC
                  ) AS rn
                 FROM warehouse.canonical_observations c) co
        WHERE (rn = 1)
    SQL
  end

  def down
    replace_period_basis_checks(PERIOD_BASES_WITHOUT_MONTH)

    execute "DROP INDEX IF EXISTS warehouse.idx_extracted_observations_unique"
    execute <<~SQL
      CREATE UNIQUE INDEX idx_extracted_observations_unique
        ON warehouse.extracted_observations (
          measure_id, measurement_year, value_type, period_basis, document_id,
          composition_id, component_id, observed_organization_id, geo_boundary_id,
          jurisdiction_id
        ) NULLS NOT DISTINCT
    SQL

    execute "DROP VIEW warehouse.measure_facts"
    execute <<~SQL
      CREATE VIEW warehouse.measure_facts AS
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

  private

  def replace_period_basis_checks(allowed_values)
    values_sql = allowed_values.map { |v| "'#{v}'::character varying" }.join(", ")

    {
      "extracted_observations" => "extracted_observations_period_basis_check",
      "canonical_observations" => "canonical_observations_period_basis_check"
    }.each do |table, constraint|
      execute "ALTER TABLE warehouse.#{table} DROP CONSTRAINT IF EXISTS #{constraint}"
      execute <<~SQL
        ALTER TABLE warehouse.#{table}
          ADD CONSTRAINT #{constraint}
          CHECK (period_basis::text = ANY (ARRAY[#{values_sql}]::text[]))
      SQL
    end
  end
end
