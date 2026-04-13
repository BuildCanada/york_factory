class AddTrigramIndexesToAddresses < ActiveRecord::Migration[8.1]
  def up
    enable_extension "pg_trgm"

    execute <<~SQL
      CREATE INDEX idx_addresses_street_name_trgm ON warehouse.addresses USING gin (street_name gin_trgm_ops);
      CREATE INDEX idx_addresses_city_trgm ON warehouse.addresses USING gin (city gin_trgm_ops);
    SQL
  end

  def down
    execute <<~SQL
      DROP INDEX IF EXISTS warehouse.idx_addresses_street_name_trgm;
      DROP INDEX IF EXISTS warehouse.idx_addresses_city_trgm;
    SQL
  end
end
