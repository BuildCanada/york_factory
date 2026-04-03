class CreateMetricsTwitterStats < ActiveRecord::Migration[8.1]
  def change
    create_table :metrics_twitter_stats do |t|
      t.string  :account,        null: false
      t.date    :date,           null: false
      t.integer :impressions,    null: false, default: 0
      t.integer :likes,          null: false, default: 0
      t.integer :engagements,    null: false, default: 0
      t.integer :bookmarks,      null: false, default: 0
      t.integer :shares,         null: false, default: 0
      t.integer :new_follows,    null: false, default: 0
      t.integer :unfollows,      null: false, default: 0
      t.integer :replies,        null: false, default: 0
      t.integer :reposts,        null: false, default: 0
      t.integer :profile_visits, null: false, default: 0
      t.integer :create_post,    null: false, default: 0
      t.integer :video_views,    null: false, default: 0
      t.integer :media_views,    null: false, default: 0

      t.timestamps
    end

    add_index :metrics_twitter_stats, [:account, :date], unique: true
  end
end
