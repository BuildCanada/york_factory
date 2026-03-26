class CreateTestimonials < ActiveRecord::Migration[8.1]
  def change
    create_table :testimonials do |t|
      t.string :name, null: false
      t.jsonb :quote_translations, default: {}
      t.integer :position, default: 0

      t.timestamps
    end
    add_index :testimonials, :position
  end
end
