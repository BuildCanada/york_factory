class CreateBuilders < ActiveRecord::Migration[8.1]
  def change
    create_table :builders do |t|
      t.string :slug, null: false
      t.string :title_en
      t.string :title_fr
      t.text :byline_en
      t.text :byline_fr
      t.text :quote_en
      t.text :quote_fr
      t.datetime :published_at

      t.timestamps
    end
    add_index :builders, :slug, unique: true
  end
end
