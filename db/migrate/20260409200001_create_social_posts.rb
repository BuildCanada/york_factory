class CreateSocialPosts < ActiveRecord::Migration[8.1]
  def change
    create_table :social_posts do |t|
      t.string :type, null: false
      t.string :account_handle, null: false
      t.string :external_id, null: false
      t.string :title
      t.text :body
      t.string :url, null: false
      t.string :image_url
      t.string :author_name
      t.string :author_avatar_url
      t.text :embed_code
      t.jsonb :metadata, default: {}
      t.datetime :posted_at, null: false

      t.timestamps
    end

    add_index :social_posts, [ :type, :external_id ], unique: true
    add_index :social_posts, [ :type, :account_handle ]
    add_index :social_posts, :posted_at, order: :desc
  end
end
