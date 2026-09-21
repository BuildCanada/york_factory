class CreateBroadcastBackfillRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :broadcast_backfill_requests do |t|
      t.references :requested_by, null: false, foreign_key: { to_table: :users }
      t.string :scope, null: false
      t.string :mode, null: false
      t.string :state, null: false, default: "queued"
      t.date :starts_on
      t.date :ends_on
      t.integer :discovered_count, null: false, default: 0
      t.integer :queued_count, null: false, default: 0
      t.integer :completed_count, null: false, default: 0
      t.integer :failed_count, null: false, default: 0
      t.integer :skipped_count, null: false, default: 0
      t.integer :processed_dates, null: false, default: 0
      t.boolean :orchestration_complete, null: false, default: false
      t.string :lease_token
      t.timestamptz :lease_expires_at
      t.text :error
      t.timestamptz :started_at
      t.timestamptz :finished_at
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_index :broadcast_backfill_requests, %i[state created_at]
    add_check_constraint :broadcast_backfill_requests,
      "scope IN ('date_range','stream')", name: "broadcast_backfill_requests_scope"
    add_check_constraint :broadcast_backfill_requests,
      "mode IN ('discover_only','discover_and_queue')", name: "broadcast_backfill_requests_mode"
    add_check_constraint :broadcast_backfill_requests,
      "state IN ('queued','running','completed','failed')", name: "broadcast_backfill_requests_state"
    add_check_constraint :broadcast_backfill_requests,
      "(scope = 'date_range' AND starts_on IS NOT NULL AND ends_on IS NOT NULL) OR (scope = 'stream' AND starts_on IS NULL AND ends_on IS NULL)",
      name: "broadcast_backfill_requests_range"

    create_table :broadcast_backfill_items do |t|
      t.references :request, null: false, foreign_key: { to_table: :broadcast_backfill_requests }
      t.bigint :media_stream_id, null: false
      t.string :state, null: false, default: "discovered"
      t.text :error
      t.timestamptz :queued_at
      t.timestamptz :started_at
      t.timestamptz :finished_at
      t.timestamps
    end
    add_index :broadcast_backfill_items, %i[request_id media_stream_id], unique: true,
      name: "idx_broadcast_backfill_items_request_stream"
    add_index :broadcast_backfill_items, %i[request_id state]
    add_foreign_key :broadcast_backfill_items, "warehouse.media_streams", column: :media_stream_id
    add_check_constraint :broadcast_backfill_items,
      "state IN ('discovered','queued','running','completed','failed','skipped')",
      name: "broadcast_backfill_items_state"
    add_check_constraint :broadcast_backfill_requests,
      "(lease_token IS NULL) = (lease_expires_at IS NULL)", name: "broadcast_backfill_requests_lease_pair"
  end
end
