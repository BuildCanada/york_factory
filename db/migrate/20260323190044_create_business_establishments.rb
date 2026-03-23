class CreateBusinessEstablishments < ActiveRecord::Migration[8.1]
  def change
    create_table :business_establishments do |t|
      t.string :business_name, null: false
      t.string :trade_name
      t.string :business_number
      t.string :naics_code
      t.string :naics_description
      t.string :employee_size_range
      t.string :address
      t.string :city
      t.string :province, null: false
      t.string :postal_code
      t.decimal :latitude, precision: 10, scale: 7
      t.decimal :longitude, precision: 10, scale: 7
      t.string :source_system, default: "odbiz"
      t.jsonb :raw_data, default: {}
      t.references :corporate_entity, foreign_key: true, null: true
      t.references :standardized_address, foreign_key: true, null: true
      t.references :raw_ingestion, foreign_key: true, null: true
      t.timestamps
    end

    add_index :business_establishments, :business_name
    add_index :business_establishments, :business_number
    add_index :business_establishments, :naics_code
    add_index :business_establishments, :province
    add_index :business_establishments, :postal_code
    add_index :business_establishments, [:business_number], unique: true,
      where: "business_number IS NOT NULL", name: "idx_biz_est_bn_unique"
  end
end
