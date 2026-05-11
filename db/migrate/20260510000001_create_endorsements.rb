class CreateEndorsements < ActiveRecord::Migration[8.1]
  def change
    create_table :endorsements do |t|
      t.references :memo, null: false, foreign_key: true
      t.string  :linkedin_sub,  null: false
      t.string  :name,          null: false
      t.string  :given_name
      t.string  :family_name
      t.string  :email
      t.boolean :email_verified, null: false, default: false
      t.string  :picture_url
      t.string  :postal_code,   null: false

      t.timestamps
    end

    add_index :endorsements, [ :memo_id, :linkedin_sub ], unique: true
    add_index :endorsements, [ :memo_id, :created_at ]
  end
end
