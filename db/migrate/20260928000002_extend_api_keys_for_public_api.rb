# Extends the existing ApiKey (yfu_) into the public data API key
# (docs/public-interface-design.md §4.1, §4.3) instead of adding a third
# token system. Existing keys are backfilled onto their owner's personal
# account with scopes ['cms:drafts'] and issuer 'local', so draft-memo agents
# keep working.
class ExtendApiKeysForPublicApi < ActiveRecord::Migration[8.1]
  def up
    change_table :api_keys, bulk: true do |t|
      t.references :account, foreign_key: true
      t.string :scopes, array: true, null: false, default: []
      t.string :issuer, null: false, default: "local"
      t.string :bifrost_vk_id
      t.timestamptz :expires_at
      t.references :rotated_from, foreign_key: { to_table: :api_keys }
      t.timestamptz :grace_until
      t.string :allowed_origins, array: true, null: false, default: []
      t.string :allowed_ips, array: true, null: false, default: []
      t.inet :last_used_ip
      t.string :revoked_reason
    end

    add_check_constraint :api_keys, "issuer IN ('bifrost','local')", name: "api_keys_issuer"
    add_index :api_keys, :bifrost_vk_id, unique: true, where: "bifrost_vk_id IS NOT NULL"
    add_index :api_keys, :token_prefix

    # A rotated key keeps its name during the grace period, so names are unique
    # only among live keys that aren't being rotated out.
    remove_index :api_keys, %i[user_id name]
    add_index :api_keys, %i[account_id name], unique: true,
      where: "revoked_at IS NULL AND grace_until IS NULL", name: "index_api_keys_on_account_and_live_name"

    execute <<~SQL
      INSERT INTO accounts (name, kind, plan, personal_user_id, created_at, updated_at)
      SELECT COALESCE(NULLIF(users.name, ''), users.email), 'personal',
             CASE WHEN users.role IN ('admin', 'superadmin') THEN 'internal' ELSE 'free' END,
             users.id, now(), now()
      FROM users
      WHERE NOT EXISTS (SELECT 1 FROM accounts WHERE accounts.personal_user_id = users.id);

      INSERT INTO account_memberships (account_id, user_id, role, created_at, updated_at)
      SELECT accounts.id, accounts.personal_user_id, 'owner', now(), now()
      FROM accounts
      WHERE accounts.kind = 'personal'
        AND NOT EXISTS (
          SELECT 1 FROM account_memberships m
          WHERE m.account_id = accounts.id AND m.user_id = accounts.personal_user_id
        );

      UPDATE api_keys
      SET account_id = accounts.id, scopes = ARRAY['cms:drafts']::varchar[], issuer = 'local'
      FROM accounts
      WHERE accounts.personal_user_id = api_keys.user_id AND api_keys.account_id IS NULL;
    SQL

    change_column_null :api_keys, :account_id, false
  end

  def down
    remove_index :api_keys, name: "index_api_keys_on_account_and_live_name"
    add_index :api_keys, %i[user_id name], unique: true
    remove_index :api_keys, :token_prefix
    remove_index :api_keys, :bifrost_vk_id
    remove_check_constraint :api_keys, name: "api_keys_issuer"
    change_table :api_keys, bulk: true do |t|
      t.remove_references :account, foreign_key: true
      t.remove_references :rotated_from, foreign_key: { to_table: :api_keys }
      t.remove :scopes, :issuer, :bifrost_vk_id, :expires_at, :grace_until,
        :allowed_origins, :allowed_ips, :last_used_ip, :revoked_reason
    end
  end
end
