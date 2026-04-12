class CreateAddresses < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE TABLE warehouse.addresses (
        id bigserial PRIMARY KEY,
        oda_uid varchar NOT NULL,
        street_number varchar,
        street_name varchar,
        street_type varchar,
        street_direction varchar,
        unit varchar,
        city varchar,
        province_code varchar(2),
        postal_code varchar(7),
        full_address varchar,
        csd_uid varchar,
        csd_name varchar,
        latitude decimal(10,7),
        longitude decimal(11,7),
        provider varchar,
        raw_ingestion_id bigint REFERENCES warehouse.raw_ingestions(id),
        created_at timestamp(6) NOT NULL,
        updated_at timestamp(6) NOT NULL
      )
    SQL

    add_index "warehouse.addresses", :oda_uid, unique: true, name: "idx_addresses_oda_uid"
    add_index "warehouse.addresses", :postal_code, name: "idx_addresses_postal_code"
    add_index "warehouse.addresses", :province_code, name: "idx_addresses_province_code"
    add_index "warehouse.addresses", :csd_uid, name: "idx_addresses_csd_uid"
    add_index "warehouse.addresses", [ :latitude, :longitude ], name: "idx_addresses_lat_lng"

    execute "CREATE INDEX idx_addresses_city ON warehouse.addresses USING btree (lower(city))"
    execute "CREATE INDEX idx_addresses_street ON warehouse.addresses USING btree (lower(street_name))"
  end

  def down
    drop_table "warehouse.addresses"
  end
end
