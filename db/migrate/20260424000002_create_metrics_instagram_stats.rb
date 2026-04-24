class CreateMetricsInstagramStats < ActiveRecord::Migration[8.1]
  def change
    create_table :metrics_instagram_stats do |t|
      t.string  :account,        null: false, default: "build_canada"
      t.date    :date,           null: false
      t.integer :views
      t.integer :interactions
      t.integer :new_followers

      t.timestamps
    end

    add_index :metrics_instagram_stats, [ :account, :date ], unique: true
  end
end
