class CreateCensusProfiles < ActiveRecord::Migration[8.1]
  def change
    create_table "warehouse.census_profiles" do |t|
      t.integer :census_year, null: false
      t.string :geo_level, null: false
      t.string :geo_uid, null: false
      t.integer :population, null: false
      t.decimal :area_sq_km
      t.decimal :population_density_per_sq_km
      t.string :source_url, null: false
      t.string :source_sha256, null: false
      t.datetime :retrieved_at, null: false
      t.timestamps

      t.index [ :census_year, :geo_level, :geo_uid, :source_sha256 ], unique: true,
        name: "index_census_profiles_vintage_geography_source"
      t.index [ :census_year, :geo_level, :geo_uid, :retrieved_at ],
        name: "index_census_profiles_latest"
      t.check_constraint "census_year > 0", name: "census_profiles_year"
      t.check_constraint "population > 0", name: "census_profiles_population"
      t.check_constraint "area_sq_km IS NULL OR area_sq_km > 0", name: "census_profiles_area"
      t.check_constraint "population_density_per_sq_km IS NULL OR population_density_per_sq_km >= 0",
        name: "census_profiles_density"
      t.check_constraint "source_sha256 ~ '^[0-9a-f]{64}$'", name: "census_profiles_sha256"
    end
  end
end
