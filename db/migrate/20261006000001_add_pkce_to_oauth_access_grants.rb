# Lets Doorkeeper verify PKCE (RFC 7636) code challenges. Doorkeeper enables
# PKCE automatically when these columns exist; grants issued without a
# challenge are unaffected.
#
# Idempotent: the public-API OAuth work (AddMcpOauth, 20260929000001) adds the
# same two columns. Whichever lands first creates them; this migration then
# skips what already exists.
class AddPkceToOauthAccessGrants < ActiveRecord::Migration[8.1]
  def up
    add_column :oauth_access_grants, :code_challenge, :string, null: true unless column_exists?(:oauth_access_grants, :code_challenge)
    add_column :oauth_access_grants, :code_challenge_method, :string, null: true unless column_exists?(:oauth_access_grants, :code_challenge_method)
  end

  # Irreversible on purpose: another migration may own these columns.
  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
