class CreateMetricsSubstackStats < ActiveRecord::Migration[8.1]
  def change
    create_table :metrics_substack_stats do |t|
      t.date    :date,  null: false
      t.integer :views, null: false, default: 0

      t.timestamps
    end

    add_index :metrics_substack_stats, :date, unique: true
  end
end
