class ScheduleMetaMediaInsights < ActiveRecord::Migration[8.1]
  def change
    add_column :metrics_meta_accounts, :media_backfilled_at, :datetime

    change_table :metrics_meta_media, bulk: true do |t|
      t.datetime :next_insights_sync_at
      t.datetime :last_insights_synced_at
      t.datetime :insights_sync_enqueued_at
      t.datetime :insights_sync_completed_at
    end

    add_index :metrics_meta_media, :next_insights_sync_at,
      where: "insights_sync_completed_at IS NULL",
      name: "idx_metrics_meta_media_due_insights"

    reversible do |direction|
      direction.up do
        execute <<~SQL.squish
          UPDATE metrics_meta_media
          SET next_insights_sync_at = CURRENT_TIMESTAMP
          WHERE insights_sync_completed_at IS NULL
        SQL
      end
    end
  end
end
