class CreateMetricsLinkedinStats < ActiveRecord::Migration[8.1]
  def change
    create_table :metrics_linkedin_stats do |t|
      t.date    :date,                       null: false
      t.integer :impressions_organic,        null: false, default: 0
      t.integer :impressions_sponsored,      null: false, default: 0
      t.integer :impressions_total,          null: false, default: 0
      t.integer :unique_impressions_organic, null: false, default: 0
      t.integer :clicks_organic,             null: false, default: 0
      t.integer :clicks_sponsored,           null: false, default: 0
      t.integer :clicks_total,               null: false, default: 0
      t.integer :reactions_organic,          null: false, default: 0
      t.integer :reactions_sponsored,        null: false, default: 0
      t.integer :reactions_total,            null: false, default: 0
      t.integer :comments_organic,           null: false, default: 0
      t.integer :comments_sponsored,         null: false, default: 0
      t.integer :comments_total,             null: false, default: 0
      t.integer :reposts_organic,            null: false, default: 0
      t.integer :reposts_sponsored,          null: false, default: 0
      t.integer :reposts_total,              null: false, default: 0
      t.decimal :engagement_rate_organic,    precision: 8, scale: 6
      t.decimal :engagement_rate_sponsored,  precision: 8, scale: 6
      t.decimal :engagement_rate_total,      precision: 8, scale: 6

      t.timestamps
    end

    add_index :metrics_linkedin_stats, :date, unique: true
  end
end
