class CreateIdentitiesAndBackfill < ActiveRecord::Migration[8.1]
  # Moves OAuth identities off the single users.provider/users.uid pair onto a
  # one-to-many identities table so a user can link multiple providers
  # (LinkedIn, Google, Discord, …) while keeping their password login.
  def up
    create_table :identities do |t|
      t.references :user, null: false, foreign_key: true
      t.string :provider, null: false
      t.string :uid, null: false
      t.string :email
      t.string :avatar_url

      t.timestamps
    end
    add_index :identities, [ :provider, :uid ], unique: true

    # Backfill existing linked identities.
    execute(<<~SQL)
      INSERT INTO identities (user_id, provider, uid, email, avatar_url, created_at, updated_at)
      SELECT id, provider, uid, email, avatar_url, NOW(), NOW()
      FROM users
      WHERE provider IS NOT NULL AND uid IS NOT NULL
    SQL

    # Dropping the columns also drops index_users_on_provider_and_uid.
    remove_column :users, :provider, :string
    remove_column :users, :uid, :string
  end

  def down
    add_column :users, :provider, :string
    add_column :users, :uid, :string
    add_index :users, [ :provider, :uid ], unique: true, name: :index_users_on_provider_and_uid

    # Collapse back to one identity per user (arbitrary if several are linked).
    execute(<<~SQL)
      UPDATE users u
      SET provider = i.provider,
          uid = i.uid,
          avatar_url = COALESCE(u.avatar_url, i.avatar_url)
      FROM identities i
      WHERE i.user_id = u.id
    SQL

    drop_table :identities
  end
end
