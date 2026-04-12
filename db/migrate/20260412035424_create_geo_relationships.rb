class CreateGeoRelationships < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE TABLE warehouse.geo_relationships (
        id bigserial PRIMARY KEY,
        da_id bigint NOT NULL REFERENCES warehouse.geo_boundaries(id),
        parent_id bigint NOT NULL REFERENCES warehouse.geo_boundaries(id),
        relationship_type varchar NOT NULL,
        raw_ingestion_id bigint REFERENCES warehouse.raw_ingestions(id),
        created_at timestamp(6) NOT NULL,
        updated_at timestamp(6) NOT NULL
      )
    SQL

    add_index "warehouse.geo_relationships", :da_id
    add_index "warehouse.geo_relationships", :parent_id
    add_index "warehouse.geo_relationships", :raw_ingestion_id
    add_index "warehouse.geo_relationships", [ :da_id, :parent_id, :relationship_type ], unique: true, name: "idx_geo_relationships_unique"
  end

  def down
    drop_table "warehouse.geo_relationships"
  end
end
