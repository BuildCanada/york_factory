class CreateEngagements < ActiveRecord::Migration[8.1]
  def change
    create_table :engagements do |t|
      t.string  :type,           null: false
      t.references :memo, null: false, foreign_key: true
      t.string  :linkedin_sub,   null: false
      t.string  :name,           null: false
      t.string  :given_name
      t.string  :family_name
      t.string  :email
      t.boolean :email_verified, null: false, default: false
      t.string  :picture_url
      t.string  :postal_code,    null: false
      t.text    :body
      t.integer :status,         null: false, default: 0
      t.datetime :published_at
      t.references :moderated_by, foreign_key: { to_table: :users }
      t.datetime :moderated_at

      t.timestamps
    end

    # One engagement of each type per person per memo (a person may both
    # endorse and critique the same memo, hence :type is part of the key).
    add_index :engagements, [ :memo_id, :type, :linkedin_sub ], unique: true
    add_index :engagements, [ :memo_id, :type, :status, :created_at ]
  end
end
