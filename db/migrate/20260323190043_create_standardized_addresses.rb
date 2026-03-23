class CreateStandardizedAddresses < ActiveRecord::Migration[8.1]
  def change
    create_table :standardized_addresses do |t|
      t.string :full_address, null: false
      t.string :street_name
      t.string :street_number
      t.string :unit_number
      t.string :city, null: false
      t.string :province, null: false
      t.string :postal_code, null: false
      t.string :country, default: "CA"
      t.decimal :latitude, precision: 10, scale: 7
      t.decimal :longitude, precision: 10, scale: 7
      t.string :census_subdivision_name
      t.string :census_subdivision_type
      t.string :source_id
      t.references :raw_ingestion, foreign_key: true, null: true
      t.timestamps
    end

    add_index :standardized_addresses, :postal_code
    add_index :standardized_addresses, :city
    add_index :standardized_addresses, :province
    add_index :standardized_addresses, [:latitude, :longitude], name: "idx_addresses_lat_lon"
    add_index :standardized_addresses, :source_id, unique: true
    add_index :standardized_addresses, [:postal_code, :street_name], name: "idx_addresses_postal_street"
  end
end
