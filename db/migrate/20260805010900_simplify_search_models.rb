class SimplifySearchModels < ActiveRecord::Migration[8.1]
  SEARCH_METADATA_COLUMNS = %i[
    search_revision search_index_sequence search_synced_at search_content_hash
    search_embedding_model search_embedding_input_hash search_embedding_scope
    search_embedding_input_tokens
  ].freeze

  def up
    add_measure_search_metadata
    flatten_notification_batches
    rename_match_snapshots
    remove_unused_columns
    remove_observation_search_metadata
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
      "KPI observations and notification joins were intentionally removed"
  end

  private

  def add_measure_search_metadata
    table = "warehouse.measures"
    add_column table, :search_revision, :integer, null: false, default: 0
    add_column table, :search_index_sequence, :bigint
    add_column table, :search_synced_at, :timestamptz
    add_column table, :search_content_hash, :string
    add_column table, :search_embedding_model, :string
    add_column table, :search_embedding_input_hash, :string
    add_column table, :search_embedding_scope, :string
    add_column table, :search_embedding_input_tokens, :integer
    add_index table, [ :search_synced_at, :search_index_sequence ],
      name: "idx_measures_search_sync"
  end

  def flatten_notification_batches
    add_reference :saved_search_matches, :notification_batch,
      foreign_key: true, index: true
    execute <<~SQL.squish
      UPDATE saved_search_matches AS matches
      SET notification_batch_id = memberships.notification_batch_id
      FROM notification_batch_matches AS memberships
      WHERE memberships.saved_search_match_id = matches.id
    SQL
    drop_table :notification_batch_matches
    remove_reference :notification_batches, :user, foreign_key: true
  end

  def rename_match_snapshots
    rename_column :saved_search_matches, :document_revision, :searchable_revision
    rename_column :saved_search_matches, :document_content_hash, :searchable_content_hash
  end

  def remove_unused_columns
    remove_column :saved_search_runs, :continuation
    remove_column :search_source_fetches, :items_changed
    remove_column :search_source_fetches, :archive_key
  end

  def remove_observation_search_metadata
    execute <<~SQL.squish
      DELETE FROM saved_search_matches
      WHERE searchable_type IN ('Warehouse::CanonicalObservation', 'Warehouse::KpiDocument')
    SQL

    %w[warehouse.canonical_observations warehouse.kpi_documents].each do |table|
      remove_index table, name: "idx_#{table.split('.').last}_search_sync"
      SEARCH_METADATA_COLUMNS.reverse_each { |column| remove_column table, column }
    end
  end
end
