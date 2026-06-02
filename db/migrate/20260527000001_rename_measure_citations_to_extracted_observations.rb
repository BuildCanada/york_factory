class RenameMeasureCitationsToExtractedObservations < ActiveRecord::Migration[8.1]
  def up
    execute "ALTER TABLE warehouse.measure_citations RENAME TO extracted_observations"

    execute "ALTER INDEX warehouse.idx_measure_citations_unique RENAME TO idx_extracted_observations_unique"
    execute "ALTER INDEX warehouse.idx_measure_citations_measure_year RENAME TO idx_extracted_observations_measure_year"
    execute "ALTER INDEX warehouse.idx_measure_citations_document RENAME TO idx_extracted_observations_document"

    execute "ALTER TABLE warehouse.extracted_observations RENAME CONSTRAINT measure_citations_value_type_check TO extracted_observations_value_type_check"
    execute "ALTER TABLE warehouse.extracted_observations RENAME CONSTRAINT measure_citations_period_basis_check TO extracted_observations_period_basis_check"

    execute "ALTER TABLE warehouse.extracted_observations RENAME COLUMN value_raw_text TO value_raw"
    execute "ALTER TABLE warehouse.extracted_observations RENAME COLUMN page_number TO source_page"

    execute <<~SQL
      ALTER TABLE warehouse.extracted_observations
        ADD COLUMN reporting_organization_id   bigint REFERENCES warehouse.organizations(id),
        ADD COLUMN responsible_organization_id bigint REFERENCES warehouse.organizations(id),
        ADD COLUMN observed_organization_id    bigint REFERENCES warehouse.organizations(id),
        ADD COLUMN reporting_organization_raw   varchar,
        ADD COLUMN responsible_organization_raw varchar,
        ADD COLUMN observed_organization_raw    varchar,
        ADD COLUMN geo_boundary_id  bigint REFERENCES warehouse.geo_boundaries(id),
        ADD COLUMN jurisdiction_id  bigint REFERENCES warehouse.jurisdictions(id),
        ADD COLUMN geography_name_raw   varchar,
        ADD COLUMN jurisdiction_name_raw varchar,
        ADD COLUMN metric_name_raw  varchar,
        ADD COLUMN period_label_raw varchar,
        ADD COLUMN unit_raw         varchar,
        ADD COLUMN period_start date,
        ADD COLUMN period_end   date,
        ADD COLUMN period_type  varchar,
        ADD COLUMN source_section varchar,
        ADD COLUMN source_table   varchar,
        ADD COLUMN source_chart   varchar,
        ADD COLUMN evidence_quote text,
        ADD COLUMN extraction_confidence numeric,
        ADD COLUMN needs_review  boolean NOT NULL DEFAULT false,
        ADD COLUMN review_status varchar NOT NULL DEFAULT 'pending'
    SQL

    execute <<~SQL
      ALTER TABLE warehouse.extracted_observations
        ADD CONSTRAINT extracted_observations_review_status_check
          CHECK (review_status IN ('pending','approved','rejected','superseded')),
        ADD CONSTRAINT extracted_observations_confidence_range
          CHECK (extraction_confidence IS NULL OR (extraction_confidence >= 0 AND extraction_confidence <= 1))
    SQL

    execute "UPDATE warehouse.extracted_observations SET needs_review = true, review_status = 'pending'"

    add_index "warehouse.extracted_observations", :review_status,
              name: "idx_extracted_observations_review_status"
    add_index "warehouse.extracted_observations", :needs_review,
              where: "needs_review = true",
              name: "idx_extracted_observations_needs_review"
    add_index "warehouse.extracted_observations", :observed_organization_id,
              name: "idx_extracted_observations_observed_org"
    add_index "warehouse.extracted_observations", :reporting_organization_id,
              name: "idx_extracted_observations_reporting_org"
    add_index "warehouse.extracted_observations", :geo_boundary_id,
              name: "idx_extracted_observations_geo_boundary"
    add_index "warehouse.extracted_observations", :jurisdiction_id,
              name: "idx_extracted_observations_jurisdiction"
  end

  def down
    %w[
      idx_extracted_observations_jurisdiction
      idx_extracted_observations_geo_boundary
      idx_extracted_observations_reporting_org
      idx_extracted_observations_observed_org
      idx_extracted_observations_needs_review
      idx_extracted_observations_review_status
    ].each { |i| execute "DROP INDEX IF EXISTS warehouse.#{i}" }

    execute "ALTER TABLE warehouse.extracted_observations DROP CONSTRAINT IF EXISTS extracted_observations_review_status_check"
    execute "ALTER TABLE warehouse.extracted_observations DROP CONSTRAINT IF EXISTS extracted_observations_confidence_range"

    %w[
      reporting_organization_id responsible_organization_id observed_organization_id
      reporting_organization_raw responsible_organization_raw observed_organization_raw
      geo_boundary_id jurisdiction_id
      geography_name_raw jurisdiction_name_raw
      metric_name_raw period_label_raw unit_raw
      period_start period_end period_type
      source_section source_table source_chart evidence_quote
      extraction_confidence needs_review review_status
    ].each { |c| execute "ALTER TABLE warehouse.extracted_observations DROP COLUMN IF EXISTS #{c}" }

    execute "ALTER TABLE warehouse.extracted_observations RENAME COLUMN source_page TO page_number"
    execute "ALTER TABLE warehouse.extracted_observations RENAME COLUMN value_raw TO value_raw_text"

    execute "ALTER TABLE warehouse.extracted_observations RENAME CONSTRAINT extracted_observations_value_type_check TO measure_citations_value_type_check"
    execute "ALTER TABLE warehouse.extracted_observations RENAME CONSTRAINT extracted_observations_period_basis_check TO measure_citations_period_basis_check"

    execute "ALTER INDEX warehouse.idx_extracted_observations_unique RENAME TO idx_measure_citations_unique"
    execute "ALTER INDEX warehouse.idx_extracted_observations_measure_year RENAME TO idx_measure_citations_measure_year"
    execute "ALTER INDEX warehouse.idx_extracted_observations_document RENAME TO idx_measure_citations_document"

    execute "ALTER TABLE warehouse.extracted_observations RENAME TO measure_citations"
  end
end
