class RepointMeasureFactsViewToCanonical < ActiveRecord::Migration[8.1]
  def up
    execute "DROP VIEW IF EXISTS warehouse.measure_facts"

    execute <<~SQL
      CREATE VIEW warehouse.measure_facts AS
      SELECT
        co.id           AS canonical_observation_id,
        co.measure_id,
        co.measurement_year,
        co.value_type,
        co.period_basis,
        co.value_numeric,
        co.value_text,
        co.document_id,
        co.extracted_observation_id,
        co.observed_organization_id,
        co.geo_boundary_id,
        co.jurisdiction_id,
        co.status,
        co.vintage_date,
        co.approved_at
      FROM (
        SELECT
          c.*,
          ROW_NUMBER() OVER (
            PARTITION BY c.measure_id, c.measurement_year, c.value_type, c.period_basis,
                         c.observed_organization_id, c.geo_boundary_id
            ORDER BY c.vintage_date  DESC NULLS LAST,
                     c.approved_at   DESC,
                     c.id            DESC
          ) AS rn
        FROM warehouse.canonical_observations c
      ) co
      WHERE co.rn = 1
    SQL
  end

  def down
    execute "DROP VIEW IF EXISTS warehouse.measure_facts"

    execute <<~SQL
      CREATE VIEW warehouse.measure_facts AS
      SELECT measure_id, measurement_year, value_type, period_basis,
             value_numeric, value_text, citation_id, document_id
      FROM (
        SELECT
          c.measure_id,
          c.measurement_year,
          c.value_type,
          c.period_basis,
          c.value_numeric,
          c.value_text,
          c.id AS citation_id,
          c.document_id,
          ROW_NUMBER() OVER (
            PARTITION BY c.measure_id, c.measurement_year, c.value_type, c.period_basis
            ORDER BY d.published_at DESC NULLS LAST,
                     d.fiscal_year DESC,
                     c.id DESC
          ) AS rn
        FROM warehouse.extracted_observations c
        JOIN warehouse.kpi_documents d ON d.id = c.document_id
      ) ranked
      WHERE rn = 1
    SQL
  end
end
