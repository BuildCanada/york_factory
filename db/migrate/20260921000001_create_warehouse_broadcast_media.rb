class CreateWarehouseBroadcastMedia < ActiveRecord::Migration[8.1]
  def change
    create_table "warehouse.media_streams" do |t|
      t.string :provider, null: false
      t.string :external_id, null: false
      t.string :kind, null: false
      t.text :title_en
      t.text :title_fr
      t.text :description_en
      t.text :description_fr
      t.text :page_url_en
      t.text :page_url_fr
      t.text :manifest_url
      t.string :provider_state
      t.timestamptz :scheduled_start_at
      t.timestamptz :first_seen_at, null: false
      t.timestamptz :last_seen_at, null: false
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_index "warehouse.media_streams", %i[provider external_id], unique: true,
      name: "idx_media_streams_provider_external"
    add_index "warehouse.media_streams", %i[kind scheduled_start_at],
      name: "idx_media_streams_kind_schedule"
    add_check_constraint "warehouse.media_streams",
      "kind IN ('continuous','event','on_demand')", name: "media_streams_kind"
    add_check_constraint "warehouse.media_streams", "last_seen_at >= first_seen_at",
      name: "media_streams_seen_range"

    create_table "warehouse.media_tracks" do |t|
      t.references :media_stream, null: false, index: false
      t.string :track_key, null: false
      t.string :kind, null: false
      t.string :language, null: false, default: "und"
      t.string :role, null: false
      t.string :delivery, null: false
      t.bigint :parent_track_id
      t.text :playlist_url
      t.string :codec
      t.jsonb :metadata, null: false, default: {}
      t.timestamptz :first_seen_at, null: false
      t.timestamptz :last_seen_at, null: false
      t.timestamps
    end
    add_index "warehouse.media_tracks", %i[media_stream_id track_key], unique: true,
      name: "idx_media_tracks_stream_key"
    add_index "warehouse.media_tracks", :parent_track_id
    add_foreign_key "warehouse.media_tracks", "warehouse.media_streams", column: :media_stream_id
    add_foreign_key "warehouse.media_tracks", "warehouse.media_tracks", column: :parent_track_id
    add_check_constraint "warehouse.media_tracks", "kind IN ('video','audio','captions')",
      name: "media_tracks_kind"
    add_check_constraint "warehouse.media_tracks", "language IN ('en','fr','mul','und')",
      name: "media_tracks_language"
    add_check_constraint "warehouse.media_tracks", "delivery IN ('separate','embedded')",
      name: "media_tracks_delivery"
    add_check_constraint "warehouse.media_tracks", "parent_track_id IS NULL OR parent_track_id <> id",
      name: "media_tracks_parent_not_self"
    add_check_constraint "warehouse.media_tracks", "last_seen_at >= first_seen_at",
      name: "media_tracks_seen_range"

    create_table "warehouse.media_objects" do |t|
      t.references :media_stream, null: false, index: false
      t.references :media_track, index: false
      t.string :kind, null: false
      t.string :identity_key, null: false
      t.text :object_key, null: false
      t.string :checksum, null: false
      t.bigint :byte_size, null: false
      t.string :content_type, null: false
      t.timestamptz :starts_at
      t.timestamptz :ends_at
      t.integer :epoch, null: false, default: 0
      t.bigint :sequence
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_index "warehouse.media_objects", %i[media_stream_id identity_key], unique: true,
      name: "idx_media_objects_stream_identity"
    add_index "warehouse.media_objects", :object_key, unique: true,
      name: "idx_media_objects_object_key"
    add_index "warehouse.media_objects", %i[media_track_id starts_at ends_at],
      name: "idx_media_objects_track_time"
    add_index "warehouse.media_objects", %i[media_stream_id kind starts_at],
      name: "idx_media_objects_stream_kind_time"
    add_foreign_key "warehouse.media_objects", "warehouse.media_streams", column: :media_stream_id
    add_foreign_key "warehouse.media_objects", "warehouse.media_tracks", column: :media_track_id
    add_check_constraint "warehouse.media_objects",
      "kind IN ('source_segment','init','manifest','playback_part','caption_file')",
      name: "media_objects_kind"
    add_check_constraint "warehouse.media_objects", "byte_size >= 0",
      name: "media_objects_byte_size"
    add_check_constraint "warehouse.media_objects", "epoch >= 0", name: "media_objects_epoch"
    add_check_constraint "warehouse.media_objects",
      "starts_at IS NULL OR ends_at IS NULL OR ends_at > starts_at",
      name: "media_objects_time_range"

    create_table "warehouse.media_recordings" do |t|
      t.references :media_stream, null: false, index: false
      t.string :recording_key, null: false
      t.timestamptz :starts_at, null: false
      t.timestamptz :ends_at
      t.string :state, null: false, default: "open"
      t.text :title_en
      t.text :title_fr
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_index "warehouse.media_recordings", %i[media_stream_id recording_key], unique: true,
      name: "idx_media_recordings_stream_key"
    add_index "warehouse.media_recordings", %i[media_stream_id starts_at ends_at],
      name: "idx_media_recordings_stream_time"
    add_foreign_key "warehouse.media_recordings", "warehouse.media_streams", column: :media_stream_id
    add_check_constraint "warehouse.media_recordings", "state IN ('open','finalized','partial')",
      name: "media_recordings_state"
    add_check_constraint "warehouse.media_recordings", "ends_at IS NULL OR ends_at > starts_at",
      name: "media_recordings_time_range"

    create_table "warehouse.media_transcript_passages" do |t|
      t.references :media_track, null: false, index: false
      t.string :window_key, null: false
      t.timestamptz :starts_at, null: false
      t.timestamptz :ends_at, null: false
      t.text :text, null: false
      t.string :state, null: false, default: "published"
      t.jsonb :metadata, null: false, default: {}
      t.integer :search_revision, null: false, default: 0
      t.bigint :search_index_sequence
      t.timestamptz :search_synced_at
      t.string :search_content_hash
      t.string :search_embedding_model
      t.string :search_embedding_input_hash
      t.string :search_embedding_scope
      t.integer :search_embedding_input_tokens
      t.timestamps
    end
    add_index "warehouse.media_transcript_passages", %i[media_track_id window_key], unique: true,
      name: "idx_media_passages_track_window"
    add_index "warehouse.media_transcript_passages", %i[media_track_id starts_at ends_at],
      name: "idx_media_passages_track_time"
    add_index "warehouse.media_transcript_passages", %i[search_synced_at search_index_sequence],
      name: "idx_media_passages_search_sync"
    add_foreign_key "warehouse.media_transcript_passages", "warehouse.media_tracks", column: :media_track_id
    add_check_constraint "warehouse.media_transcript_passages", "ends_at > starts_at",
      name: "media_passages_time_range"
    add_check_constraint "warehouse.media_transcript_passages", "state IN ('published','withdrawn')",
      name: "media_passages_state"
    add_check_constraint "warehouse.media_transcript_passages", "search_revision >= 0",
      name: "media_passages_revision"
    add_check_constraint "warehouse.media_transcript_passages",
      "search_embedding_scope IS NULL OR search_embedding_scope IN ('full','truncated')",
      name: "media_passages_embedding_scope"

    create_table :media_capture_states do |t|
      t.bigint :media_stream_id, null: false
      t.boolean :enabled, null: false, default: false
      t.timestamptz :next_poll_at
      t.string :lease_token
      t.timestamptz :lease_expires_at
      t.jsonb :cursor, null: false, default: {}
      t.integer :consecutive_failures, null: false, default: 0
      t.text :last_error
      t.timestamptz :last_captured_at
      t.timestamptz :last_processed_at
      t.timestamps
    end
    add_index :media_capture_states, :media_stream_id, unique: true
    add_index :media_capture_states, %i[enabled next_poll_at], name: "idx_media_capture_states_due"
    add_index :media_capture_states, :lease_expires_at
    add_foreign_key :media_capture_states, "warehouse.media_streams", column: :media_stream_id
    add_check_constraint :media_capture_states, "consecutive_failures >= 0",
      name: "media_capture_states_failures"
    add_check_constraint :media_capture_states,
      "(lease_token IS NULL) = (lease_expires_at IS NULL)", name: "media_capture_states_lease_pair"

    create_table :media_clips do |t|
      t.references :user, null: false, foreign_key: true
      t.bigint :media_recording_id, null: false
      t.bigint :media_track_id
      t.timestamptz :starts_at, null: false
      t.timestamptz :ends_at, null: false
      t.timestamptz :actual_starts_at
      t.timestamptz :actual_ends_at
      t.string :title, null: false
      t.string :state, null: false, default: "queued"
      t.text :error
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_index :media_clips, %i[user_id created_at]
    add_index :media_clips, :media_recording_id
    add_index :media_clips, :media_track_id
    add_foreign_key :media_clips, "warehouse.media_recordings", column: :media_recording_id
    add_foreign_key :media_clips, "warehouse.media_tracks", column: :media_track_id
    add_check_constraint :media_clips, "state IN ('queued','processing','ready','failed')",
      name: "media_clips_state"
    add_check_constraint :media_clips, "ends_at > starts_at", name: "media_clips_requested_range"
    add_check_constraint :media_clips,
      "actual_starts_at IS NULL OR actual_ends_at IS NULL OR actual_ends_at > actual_starts_at",
      name: "media_clips_actual_range"
  end
end
