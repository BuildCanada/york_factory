class CreateMetricsTiktokStats < ActiveRecord::Migration[8.1]
  def change
    create_table :metrics_tiktok_stats do |t|
      t.string  :account,       null: false, default: "build_canada"
      t.date    :date,          null: false
      t.integer :video_views,   null: false, default: 0
      t.integer :profile_views, null: false, default: 0
      t.integer :likes,         null: false, default: 0
      t.integer :comments,      null: false, default: 0
      t.integer :shares,        null: false, default: 0

      t.timestamps
    end

    add_index :metrics_tiktok_stats, [ :account, :date ], unique: true
  end
end
