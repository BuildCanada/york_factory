class CreateTeamMembers < ActiveRecord::Migration[8.1]
  def change
    create_table :team_members do |t|
      t.string :name, null: false
      t.string :slug
      t.string :title_en
      t.string :title_fr
      t.string :role
      t.string :twitter_url
      t.string :linkedin_url
      t.integer :position, default: 0
      t.datetime :published_at

      t.timestamps
    end
    add_index :team_members, :slug, unique: true
    add_index :team_members, :role
    add_index :team_members, :position
  end
end
