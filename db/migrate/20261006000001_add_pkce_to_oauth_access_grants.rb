# Lets Doorkeeper verify PKCE (RFC 7636) code challenges. Doorkeeper enables
# PKCE automatically when these columns exist; grants issued without a
# challenge are unaffected.
class AddPkceToOauthAccessGrants < ActiveRecord::Migration[8.1]
  def change
    add_column :oauth_access_grants, :code_challenge, :string, null: true
    add_column :oauth_access_grants, :code_challenge_method, :string, null: true
  end
end
