class CreateSubstackPosts < ActiveRecord::Migration[8.1]
  def change
    create_table :substack_posts do |t|
      t.string :external_url, null: false
      t.string :title, null: false
      t.string :subtitle
      t.text :body
      t.string :author_name
      t.string :image_url
      t.datetime :posted_at, null: false

      t.timestamps
    end

    add_index :substack_posts, :external_url, unique: true
    add_index :substack_posts, :posted_at, order: :desc
  end
end
