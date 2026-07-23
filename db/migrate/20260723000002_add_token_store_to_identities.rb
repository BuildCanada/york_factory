class AddTokenStoreToIdentities < ActiveRecord::Migration[8.1]
  # Dedicated OAuth token store. access_token/refresh_token are encrypted at
  # rest via ActiveRecord Encryption (text, since ciphertext is longer than the
  # raw token). Tokens are refreshed on every login and on demand.
  def up
    add_column :identities, :access_token, :text
    add_column :identities, :refresh_token, :text
    add_column :identities, :token_expires_at, :datetime
    add_column :identities, :token_scope, :string

    # Migrate any tokens previously captured inside raw into the dedicated
    # (encrypted) columns, then strip credentials out of raw.
    Identity.reset_column_information
    Identity.where.not(raw: nil).find_each do |identity|
      creds = identity.raw["credentials"]
      next if creds.blank?

      identity.access_token = creds["token"]
      identity.refresh_token = creds["refresh_token"]
      identity.token_expires_at = Time.at(creds["expires_at"]) if creds["expires_at"].present?
      identity.raw = identity.raw.except("credentials")
      identity.save!
    end
  end

  def down
    remove_column :identities, :access_token
    remove_column :identities, :refresh_token
    remove_column :identities, :token_expires_at
    remove_column :identities, :token_scope
  end
end
