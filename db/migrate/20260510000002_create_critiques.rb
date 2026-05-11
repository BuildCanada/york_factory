class CreateCritiques < ActiveRecord::Migration[8.1]
  def change
    create_table :critiques do |t|
      t.references :memo, null: false, foreign_key: true
      t.string  :linkedin_sub,  null: false
      t.string  :name,          null: false
      t.string  :given_name
      t.string  :family_name
      t.string  :email
      t.boolean :email_verified, null: false, default: false
      t.string  :picture_url
      t.string  :postal_code,   null: false
      t.text    :body,          null: false
      t.integer :status,        null: false, default: 0
      t.datetime :published_at
      t.references :moderated_by, foreign_key: { to_table: :users }
      t.datetime :moderated_at

      t.timestamps
    end

    add_index :critiques, [ :memo_id, :linkedin_sub ], unique: true
    add_index :critiques, [ :memo_id, :status, :created_at ]
  end
end
