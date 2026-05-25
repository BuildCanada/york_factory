class CreateWarehouseApiTokens < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE TABLE warehouse.api_tokens (
        id bigserial PRIMARY KEY,
        name varchar NOT NULL,
        token_hash varchar NOT NULL,
        scopes varchar[] NOT NULL DEFAULT ARRAY[]::varchar[],
        last_used_at timestamp(6),
        revoked_at timestamp(6),
        created_at timestamp(6) NOT NULL,
        updated_at timestamp(6) NOT NULL
      )
    SQL

    add_index "warehouse.api_tokens", :token_hash, unique: true
    add_index "warehouse.api_tokens", :name, unique: true
  end

  def down
    drop_table "warehouse.api_tokens"
  end
end
