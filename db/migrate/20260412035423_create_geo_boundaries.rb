class CreateGeoBoundaries < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE TABLE warehouse.geo_boundaries (
        id bigserial PRIMARY KEY,
        boundary_type varchar NOT NULL,
        geo_uid varchar NOT NULL,
        name_en varchar,
        name_fr varchar,
        province_code varchar(2),
        geometry geography(MultiPolygon, 4326),
        population integer,
        area_sq_km decimal,
        census_year integer DEFAULT 2021,
        raw_ingestion_id bigint REFERENCES warehouse.raw_ingestions(id),
        created_at timestamp(6) NOT NULL,
        updated_at timestamp(6) NOT NULL
      )
    SQL

    add_index "warehouse.geo_boundaries", [ :boundary_type, :geo_uid, :census_year ], unique: true, name: "idx_geo_boundaries_unique"
    add_index "warehouse.geo_boundaries", :boundary_type
    add_index "warehouse.geo_boundaries", :province_code

    execute "CREATE INDEX idx_geo_boundaries_geometry ON warehouse.geo_boundaries USING gist (geometry)"
  end

  def down
    drop_table "warehouse.geo_boundaries"
  end
end
