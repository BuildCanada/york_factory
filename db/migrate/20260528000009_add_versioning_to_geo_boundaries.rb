class AddVersioningToGeoBoundaries < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      ALTER TABLE warehouse.geo_boundaries
        ADD COLUMN code_system varchar,
        ADD COLUMN valid_from  date,
        ADD COLUMN valid_to    date,
        ADD CONSTRAINT geo_boundaries_valid_range
          CHECK (valid_to IS NULL OR valid_from IS NULL OR valid_to >= valid_from)
    SQL

    # Derive code_system from boundary_type + census_year for existing rows.
    execute <<~SQL
      UPDATE warehouse.geo_boundaries
      SET code_system = CASE
        WHEN census_year IS NULL THEN boundary_type
        ELSE boundary_type || '_' || census_year::text
      END
    SQL

    # NOT NULL only after backfill.
    execute "ALTER TABLE warehouse.geo_boundaries ALTER COLUMN code_system SET NOT NULL"

    add_index "warehouse.geo_boundaries", :code_system,
              name: "idx_geo_boundaries_code_system"
  end

  def down
    execute "DROP INDEX IF EXISTS warehouse.idx_geo_boundaries_code_system"
    execute "ALTER TABLE warehouse.geo_boundaries DROP CONSTRAINT IF EXISTS geo_boundaries_valid_range"
    %w[valid_to valid_from code_system].each do |c|
      execute "ALTER TABLE warehouse.geo_boundaries DROP COLUMN IF EXISTS #{c}"
    end
  end
end
