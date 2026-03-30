class CreateTestimonials < ActiveRecord::Migration[8.1]
  def change
    create_table :testimonials do |t|
      t.string :name, null: false
      t.text :quote_en
      t.text :quote_fr
      t.integer :position, default: 0
      t.datetime :published_at

      t.timestamps
    end
    add_index :testimonials, :position
  end
end
