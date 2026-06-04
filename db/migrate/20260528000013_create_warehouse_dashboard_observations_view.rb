class CreateWarehouseDashboardObservationsView < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE VIEW warehouse.dashboard_observations AS
      SELECT
        co.id AS canonical_observation_id,
        co.extracted_observation_id,
        co.measure_id,
        m.slug          AS measure_slug,
        m.canonical_name AS measure_name,
        m.category      AS measure_category,
        m.aggregation_type,
        co.metric_version_id,
        co.composition_id,
        co.component_id,
        co.measurement_year,
        co.period_start,
        co.period_end,
        co.period_type,
        co.value_type,
        co.period_basis,
        co.value_numeric,
        co.value_text,
        co.unit_id,
        u.symbol AS unit_symbol,
        co.status,
        co.vintage_date,
        co.is_total,
        co.is_residual,
        co.observed_organization_id,
        oo.slug          AS observed_organization_slug,
        oo.canonical_name AS observed_organization_name,
        co.responsible_organization_id,
        co.reporting_organization_id,
        co.jurisdiction_id,
        j.slug AS jurisdiction_slug,
        j.name AS jurisdiction_name,
        co.geo_boundary_id,
        gb.geo_uid AS geo_uid,
        gb.boundary_type,
        gb.code_system AS geo_code_system,
        co.document_id,
        d.doc_url,
        d.doc_title,
        d.fiscal_year AS document_fiscal_year,
        d.published_at AS document_published_at,
        co.approved_at,
        co.approved_by
      FROM warehouse.canonical_observations co
      JOIN warehouse.measures m ON m.id = co.measure_id
      LEFT JOIN warehouse.units u ON u.id = co.unit_id
      LEFT JOIN warehouse.organizations oo ON oo.id = co.observed_organization_id
      LEFT JOIN warehouse.jurisdictions  j  ON j.id  = co.jurisdiction_id
      LEFT JOIN warehouse.geo_boundaries gb ON gb.id = co.geo_boundary_id
      LEFT JOIN warehouse.kpi_documents  d  ON d.id  = co.document_id
    SQL
  end

  def down
    execute "DROP VIEW IF EXISTS warehouse.dashboard_observations"
  end
end
