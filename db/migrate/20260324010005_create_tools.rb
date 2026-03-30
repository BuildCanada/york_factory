class CreateTools < ActiveRecord::Migration[8.1]
  def change
    create_table :tools do |t|
      t.string :slug, null: false
      t.string :title_en
      t.string :title_fr
      t.string :url
      t.boolean :featured, default: false
      t.integer :position, default: 0
      t.string :accent_color
      t.string :size, default: "small"
      t.datetime :published_at

      t.timestamps
    end
    add_index :tools, :slug, unique: true
  end
end
