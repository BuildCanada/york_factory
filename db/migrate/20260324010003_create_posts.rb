class CreatePosts < ActiveRecord::Migration[8.1]
  def change
    create_table :posts do |t|
      t.string :slug, null: false
      t.string :title_en
      t.string :title_fr
      t.text :summary_en
      t.text :summary_fr
      t.boolean :hidden, default: false
      t.datetime :published_at

      t.timestamps
    end
    add_index :posts, :slug, unique: true
  end
end
