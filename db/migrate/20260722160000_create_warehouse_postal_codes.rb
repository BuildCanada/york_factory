class CreateWarehousePostalCodes < ActiveRecord::Migration[8.1]
  # Canadian postal code centroids (postal code → lat/long) for geocoding
  # user-supplied postal codes to ridings, wards, and other boundaries.
  # Sourced from the CanadianPostalCodes CSV (March 2024 vintage, ~900k codes).
  def up
    execute <<~SQL
      CREATE TABLE warehouse.postal_codes (
        id bigserial PRIMARY KEY,
        postal_code varchar(7) NOT NULL,
        city varchar,
        province_code varchar(2),
        time_zone_offset integer,
        latitude numeric(10,7) NOT NULL,
        longitude numeric(11,7) NOT NULL,

        created_at timestamp(6) NOT NULL,
        updated_at timestamp(6) NOT NULL
      )
    SQL
    add_index "warehouse.postal_codes", :postal_code, unique: true, name: "ux_postal_codes_postal_code"
    add_index "warehouse.postal_codes", :province_code, name: "idx_postal_codes_province_code"
    add_index "warehouse.postal_codes", [ :latitude, :longitude ], name: "idx_postal_codes_lat_lng"
  end

  def down
    drop_table "warehouse.postal_codes"
  end
end
