class CreateWarehouseMeasureFactsView < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE OR REPLACE VIEW warehouse.measure_facts AS
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
        FROM warehouse.measure_citations c
        JOIN warehouse.kpi_documents d ON d.id = c.document_id
      ) ranked
      WHERE rn = 1
    SQL
  end

  def down
    execute "DROP VIEW IF EXISTS warehouse.measure_facts"
  end
end
