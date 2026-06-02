class CreateWarehouseHumanReviewQueueView < ActiveRecord::Migration[8.1]
  SEVERITY_RANK_SQL = "CASE rf.severity " \
    "WHEN 'critical' THEN 4 WHEN 'high' THEN 3 WHEN 'medium' THEN 2 WHEN 'low' THEN 1 ELSE 0 END"

  def up
    execute <<~SQL
      CREATE VIEW warehouse.human_review_queue AS
      SELECT
        eo.id AS extracted_observation_id,
        eo.measure_id,
        eo.document_id,
        eo.agent_run_id,
        eo.measurement_year,
        eo.value_type,
        eo.period_basis,
        eo.value_numeric,
        eo.value_text,
        eo.value_raw,
        eo.unit_raw,
        eo.metric_name_raw,
        eo.geography_name_raw,
        eo.jurisdiction_name_raw,
        eo.reporting_organization_raw,
        eo.responsible_organization_raw,
        eo.observed_organization_raw,
        eo.evidence_quote,
        eo.source_page,
        eo.source_section,
        eo.source_table,
        eo.extraction_confidence,
        eo.needs_review,
        eo.review_status,
        eo.created_at,
        COUNT(rf.id) FILTER (WHERE rf.resolved_at IS NULL) AS open_flag_count,
        MAX(#{SEVERITY_RANK_SQL}) FILTER (WHERE rf.resolved_at IS NULL) AS highest_open_severity_rank,
        (ARRAY_AGG(rf.severity ORDER BY (#{SEVERITY_RANK_SQL}) DESC NULLS LAST, rf.id DESC)
          FILTER (WHERE rf.resolved_at IS NULL))[1] AS highest_open_severity,
        BOOL_OR(rf.resolved_at IS NULL) AS has_open_flags
      FROM warehouse.extracted_observations eo
      LEFT JOIN warehouse.observation_review_flags rf
        ON rf.extracted_observation_id = eo.id
      WHERE eo.review_status = 'pending'
        AND (eo.needs_review = true OR rf.id IS NOT NULL)
      GROUP BY eo.id
    SQL
  end

  def down
    execute "DROP VIEW IF EXISTS warehouse.human_review_queue"
  end
end
