class CreateGeoCrosswalks < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE TABLE warehouse.geo_crosswalks (
        id bigserial PRIMARY KEY,
        source_id bigint NOT NULL REFERENCES warehouse.geo_boundaries(id),
        target_id bigint NOT NULL REFERENCES warehouse.geo_boundaries(id),
        source_type varchar NOT NULL,
        target_type varchar NOT NULL,
        overlap_population integer,
        weight_source_to_target decimal(10,8),
        weight_target_to_source decimal(10,8),
        da_count integer,
        census_year integer DEFAULT 2021,
        created_at timestamp(6) NOT NULL,
        updated_at timestamp(6) NOT NULL
      )
    SQL

    add_index "warehouse.geo_crosswalks", [ :source_id, :target_id, :census_year ], unique: true, name: "idx_geo_crosswalks_unique"
    add_index "warehouse.geo_crosswalks", [ :source_type, :source_id ], name: "idx_geo_crosswalks_source"
    add_index "warehouse.geo_crosswalks", [ :target_type, :target_id ], name: "idx_geo_crosswalks_target"
  end

  def down
    drop_table "warehouse.geo_crosswalks"
  end
end
