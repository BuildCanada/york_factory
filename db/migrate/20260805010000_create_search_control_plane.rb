class CreateSearchControlPlane < ActiveRecord::Migration[8.1]
  def change
    create_table :search_sources do |t|
      t.string :name, null: false
      t.string :realm, null: false
      t.string :strategy, null: false
      t.text :url
      t.integer :cadence_seconds, null: false, default: 300
      t.jsonb :configuration, null: false, default: {}
      t.boolean :enabled, null: false, default: true
      t.timestamptz :next_fetch_at
      t.string :etag
      t.string :last_modified
      t.timestamptz :last_succeeded_at
      t.timestamptz :last_failed_at
      t.integer :consecutive_failures, null: false, default: 0
      t.timestamps
    end
    add_index :search_sources, :name, unique: true
    add_index :search_sources, [ :enabled, :next_fetch_at ],
      name: "idx_search_sources_due"
    add_check_constraint :search_sources, "cadence_seconds >= 60",
      name: "search_sources_cadence_minimum"
    add_check_constraint :search_sources, "consecutive_failures >= 0",
      name: "search_sources_failures_nonnegative"

    create_table :search_source_fetches do |t|
      t.references :search_source, null: false, foreign_key: true
      t.string :status, null: false, default: "pending"
      t.integer :http_status
      t.timestamptz :started_at
      t.timestamptz :finished_at
      t.integer :duration_ms
      t.integer :items_discovered, null: false, default: 0
      t.integer :items_changed, null: false, default: 0
      t.string :response_checksum
      t.string :archive_key
      t.text :error
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_index :search_source_fetches, [ :search_source_id, :created_at ],
      name: "idx_search_source_fetches_recent"
    add_check_constraint :search_source_fetches,
      "status IN ('pending','running','succeeded','failed','not_modified')",
      name: "search_source_fetches_status"

    create_table :search_documents, id: :uuid do |t|
      t.string :realm, null: false
      t.references :search_source, foreign_key: true
      t.string :external_key
      t.string :source_record_type
      t.bigint :source_record_id
      t.string :record_type, null: false
      t.string :state, null: false, default: "draft"
      t.string :visibility, null: false, default: "public"
      t.uuid :permission_ids, array: true, null: false, default: []
      t.integer :revision, null: false, default: 0
      t.bigint :index_sequence
      t.timestamptz :search_synced_at
      t.text :canonical_url
      t.string :canonical_url_digest
      t.text :source_url
      t.text :title
      t.text :summary
      t.text :content
      t.string :language, null: false, default: "und"
      t.timestamptz :published_at
      t.timestamptz :source_updated_at
      t.timestamptz :first_seen_at
      t.timestamptz :last_seen_at
      t.string :content_hash
      t.jsonb :ontology, null: false, default: {}
      t.jsonb :realm_data, null: false, default: {}
      t.string :embedding_model
      t.string :embedding_input_hash
      t.string :embedding_scope
      t.integer :embedding_input_tokens
      t.jsonb :extraction_metadata, null: false, default: {}
      t.jsonb :validation_errors, null: false, default: []
      t.timestamps
    end
    add_index :search_documents, [ :realm, :search_source_id, :external_key ],
      unique: true,
      where: "search_source_id IS NOT NULL AND external_key IS NOT NULL",
      name: "idx_search_documents_source_key"
    add_index :search_documents, [ :realm, :canonical_url_digest ],
      unique: true,
      where: "canonical_url_digest IS NOT NULL",
      name: "idx_search_documents_canonical_url"
    add_index :search_documents, [ :source_record_type, :source_record_id, :realm ],
      unique: true,
      where: "source_record_type IS NOT NULL AND source_record_id IS NOT NULL",
      name: "idx_search_documents_source_record"
    add_index :search_documents, [ :realm, :state ]
    add_index :search_documents, :index_sequence
    add_check_constraint :search_documents,
      "state IN ('draft','published','withdrawn','invalid')",
      name: "search_documents_state"
    add_check_constraint :search_documents, "revision >= 0",
      name: "search_documents_revision_nonnegative"
    add_check_constraint :search_documents,
      "embedding_scope IS NULL OR embedding_scope IN ('full','truncated')",
      name: "search_documents_embedding_scope"

    create_table :saved_searches do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.string :realm, null: false
      t.jsonb :definition, null: false, default: {}
      t.string :definition_digest, null: false
      t.integer :definition_version, null: false, default: 1
      t.boolean :enabled, null: false, default: true
      t.integer :poll_interval_seconds, null: false, default: 60
      t.timestamptz :next_run_at
      t.bigint :cursor_sequence, null: false, default: 0
      t.string :evaluation_strategy, null: false, default: "new_tail"
      t.timestamptz :last_state_evaluated_at
      t.string :start_policy, null: false, default: "future_only"
      t.boolean :notify_on_update, null: false, default: false
      t.string :delivery_mode, null: false, default: "instant"
      t.jsonb :delivery_configuration, null: false, default: { "channels" => [ "email" ] }
      t.string :timezone, null: false, default: "UTC"
      t.timestamps
    end
    add_index :saved_searches, [ :enabled, :next_run_at ],
      name: "idx_saved_searches_due"
    add_index :saved_searches, [ :user_id, :name ]
    add_check_constraint :saved_searches,
      "poll_interval_seconds BETWEEN 60 AND 86400",
      name: "saved_searches_poll_interval"
    add_check_constraint :saved_searches,
      "evaluation_strategy IN ('new_tail','current_state')",
      name: "saved_searches_evaluation_strategy"
    add_check_constraint :saved_searches,
      "start_policy IN ('future_only','backfill')",
      name: "saved_searches_start_policy"
    add_check_constraint :saved_searches,
      "delivery_mode IN ('instant','digest')",
      name: "saved_searches_delivery_mode"

    create_table :saved_search_runs do |t|
      t.references :saved_search, null: false, foreign_key: true
      t.timestamptz :scheduled_for, null: false
      t.bigint :from_sequence, null: false, default: 0
      t.bigint :to_sequence, null: false, default: 0
      t.string :status, null: false, default: "pending"
      t.jsonb :continuation, null: false, default: {}
      t.integer :query_count, null: false, default: 0
      t.integer :matched_count, null: false, default: 0
      t.integer :duration_ms
      t.jsonb :billing, null: false, default: {}
      t.jsonb :performance, null: false, default: {}
      t.text :error
      t.timestamptz :started_at
      t.timestamptz :finished_at
      t.timestamps
    end
    add_index :saved_search_runs, [ :saved_search_id, :scheduled_for ],
      unique: true, name: "idx_saved_search_runs_tick"
    add_check_constraint :saved_search_runs,
      "status IN ('pending','running','succeeded','failed')",
      name: "saved_search_runs_status"

    create_table :saved_search_matches do |t|
      t.references :saved_search, null: false, foreign_key: true
      t.references :search_document, null: false, type: :uuid, foreign_key: true
      t.integer :document_revision, null: false
      t.string :document_content_hash, null: false
      t.string :match_key, null: false
      t.timestamptz :matched_at, null: false
      t.bigint :matched_sequence
      t.jsonb :match_evidence, null: false, default: {}
      t.string :state, null: false, default: "pending"
      t.timestamps
    end
    add_index :saved_search_matches, [ :saved_search_id, :match_key ],
      unique: true, name: "idx_saved_search_matches_dedupe"
    add_index :saved_search_matches, [ :saved_search_id, :state, :matched_at ],
      name: "idx_saved_search_matches_buffer"
    add_check_constraint :saved_search_matches,
      "state IN ('pending','buffered','dispatching','delivered','dead')",
      name: "saved_search_matches_state"

    create_table :notification_batches do |t|
      t.references :saved_search, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :mode, null: false
      t.string :state, null: false, default: "open"
      t.timestamptz :scheduled_for
      t.timestamptz :closed_at
      t.boolean :coalesced, null: false, default: false
      t.timestamps
    end
    add_index :notification_batches, [ :state, :scheduled_for ],
      name: "idx_notification_batches_due"
    add_check_constraint :notification_batches,
      "mode IN ('instant','digest')", name: "notification_batches_mode"
    add_check_constraint :notification_batches,
      "state IN ('open','closed','delivering','delivered','dead')",
      name: "notification_batches_state"

    create_table :notification_batch_matches do |t|
      t.references :notification_batch, null: false, foreign_key: true
      t.references :saved_search_match, null: false, foreign_key: true
      t.timestamps
    end
    add_index :notification_batch_matches,
      [ :notification_batch_id, :saved_search_match_id ], unique: true,
      name: "idx_notification_batch_matches_unique"
    add_index :notification_batch_matches, :saved_search_match_id, unique: true,
      name: "idx_notification_batch_matches_once"

    create_table :notification_deliveries do |t|
      t.references :notification_batch, null: false, foreign_key: true
      t.string :channel, null: false
      t.string :status, null: false, default: "pending"
      t.integer :attempt_count, null: false, default: 0
      t.string :idempotency_key, null: false
      t.jsonb :provider_response, null: false, default: {}
      t.timestamptz :next_attempt_at
      t.timestamptz :delivered_at
      t.text :last_error
      t.timestamps
    end
    add_index :notification_deliveries,
      [ :notification_batch_id, :channel ], unique: true,
      name: "idx_notification_deliveries_channel"
    add_index :notification_deliveries, :idempotency_key, unique: true
    add_index :notification_deliveries, [ :status, :next_attempt_at ],
      name: "idx_notification_deliveries_ready"
    add_check_constraint :notification_deliveries,
      "channel = 'email'", name: "notification_deliveries_channel"
    add_check_constraint :notification_deliveries,
      "status IN ('pending','delivering','delivered','failed','dead')",
      name: "notification_deliveries_status"
  end
end
