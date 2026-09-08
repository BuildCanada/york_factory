class AddSourceToMetricsSubstackStats < ActiveRecord::Migration[8.1]
  def change
    change_table :metrics_substack_stats, bulk: true do |t|
      t.string :source, null: false, default: "manual_import"
      t.datetime :scraped_at
      t.jsonb :source_payload, null: false, default: {}
    end
  end
end
