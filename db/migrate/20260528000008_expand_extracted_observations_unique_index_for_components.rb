class ExpandExtractedObservationsUniqueIndexForComponents < ActiveRecord::Migration[8.1]
  def up
    execute "DROP INDEX IF EXISTS warehouse.idx_extracted_observations_unique"
    # NULLS NOT DISTINCT (PG15+) means two rows with NULL composition_id and
    # NULL component_id are treated as duplicates of each other, preserving the
    # pre-Phase-5 dedupe behavior for non-composite metrics.
    execute <<~SQL
      CREATE UNIQUE INDEX idx_extracted_observations_unique
        ON warehouse.extracted_observations (
          measure_id, measurement_year, value_type, period_basis, document_id,
          composition_id, component_id, observed_organization_id, geo_boundary_id
        ) NULLS NOT DISTINCT
    SQL
  end

  def down
    execute "DROP INDEX IF EXISTS warehouse.idx_extracted_observations_unique"
    add_index "warehouse.extracted_observations",
              %i[measure_id measurement_year value_type period_basis document_id],
              unique: true,
              name: "idx_extracted_observations_unique"
  end
end
