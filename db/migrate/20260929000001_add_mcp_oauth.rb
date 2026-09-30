# OAuth 2.1 for the MCP server and the public data API
# (docs/public-interface-design.md §4.6, workstream WS-F).
#
# - Grants get PKCE columns (Doorkeeper turns PKCE on when they exist), and
#   grants and tokens get the RFC 8707 resource (the token's audience) and the
#   account that usage is billed to.
# - Applications get the columns for Client ID Metadata Documents and dynamic
#   registration. Existing applications (TradingPost) become `first_party`
#   and behave exactly as before.
# - Audit events can be made by an OAuth client (a registration, or an
#   RFC 7009 revocation), not only by a user, an admin or the system.
class AddMcpOauth < ActiveRecord::Migration[8.1]
  def up
    change_table :oauth_access_grants, bulk: true do |t|
      t.string :code_challenge
      t.string :code_challenge_method
      t.string :resource
      t.bigint :account_id
    end

    change_table :oauth_access_tokens, bulk: true do |t|
      t.string :resource
      t.bigint :account_id
    end
    add_index :oauth_access_tokens, %i[account_id application_id]
    # Refresh-token reuse detection looks tokens up by their predecessor.
    add_index :oauth_access_tokens, :previous_refresh_token, where: "previous_refresh_token <> ''"
    add_foreign_key :oauth_access_tokens, :accounts
    add_foreign_key :oauth_access_grants, :accounts

    change_table :oauth_applications, bulk: true do |t|
      t.string :client_type, null: false, default: "first_party"
      t.bigint :account_id
      t.text :metadata_url
      t.text :resource_uris, array: true, null: false, default: []
      t.text :logo_url
      t.text :client_uri
      t.datetime :reviewed_at
      t.datetime :disabled_at
      t.datetime :metadata_fetched_at
      t.datetime :metadata_expires_at
      t.inet :registration_ip
    end
    add_index :oauth_applications, :metadata_url, unique: true, where: "metadata_url IS NOT NULL"
    add_index :oauth_applications, %i[client_type created_at]
    add_foreign_key :oauth_applications, :accounts
    add_check_constraint :oauth_applications,
      "client_type IN ('first_party','registered','dynamic','metadata_document')",
      name: "oauth_applications_client_type"

    remove_check_constraint :audit_events, name: "audit_events_actor_kind"
    add_check_constraint :audit_events,
      "actor_kind IN ('user','admin','system','client')", name: "audit_events_actor_kind"
  end

  def down
    remove_check_constraint :audit_events, name: "audit_events_actor_kind"
    add_check_constraint :audit_events,
      "actor_kind IN ('user','admin','system')", name: "audit_events_actor_kind"

    remove_check_constraint :oauth_applications, name: "oauth_applications_client_type"
    remove_foreign_key :oauth_applications, :accounts
    remove_index :oauth_applications, %i[client_type created_at]
    remove_index :oauth_applications, :metadata_url
    change_table :oauth_applications, bulk: true do |t|
      t.remove :client_type, :account_id, :metadata_url, :resource_uris, :logo_url, :client_uri,
        :reviewed_at, :disabled_at, :metadata_fetched_at, :metadata_expires_at, :registration_ip
    end

    remove_foreign_key :oauth_access_grants, :accounts
    remove_foreign_key :oauth_access_tokens, :accounts
    remove_index :oauth_access_tokens, :previous_refresh_token
    remove_index :oauth_access_tokens, %i[account_id application_id]
    change_table :oauth_access_tokens, bulk: true do |t|
      t.remove :resource, :account_id
    end
    change_table :oauth_access_grants, bulk: true do |t|
      t.remove :code_challenge, :code_challenge_method, :resource, :account_id
    end
  end
end
