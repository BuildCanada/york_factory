class ReplaceSearchOutboxWithSequence < ActiveRecord::Migration[8.1]
  def up
    execute "CREATE SEQUENCE IF NOT EXISTS search_index_sequence AS bigint"
    add_column :search_documents, :search_synced_at, :timestamptz unless column_exists?(:search_documents, :search_synced_at)
    add_index :search_documents, [ :search_synced_at, :index_sequence ],
      name: "idx_search_documents_sync_overlap" unless index_exists?(:search_documents, [ :search_synced_at, :index_sequence ])
    drop_table :search_index_events if table_exists?(:search_index_events)
    drop_table :search_namespace_states if table_exists?(:search_namespace_states)
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
      "the search outbox was replaced by direct model-owned indexing"
  end
end
