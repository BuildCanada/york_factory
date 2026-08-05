class AddSearchMetadataToSourceModels < ActiveRecord::Migration[8.1]
  TABLES = {
    "warehouse.fiscal_expenditures" => "Warehouse::FiscalExpenditure",
    "warehouse.standard_object_expenditures" => "Warehouse::StandardObjectExpenditure",
    "warehouse.canonical_observations" => "Warehouse::CanonicalObservation",
    "warehouse.kpi_documents" => "Warehouse::KpiDocument"
  }.freeze

  def up
    TABLES.each_key { |table| add_search_columns(table) }
    TABLES.each { |table, model_name| backfill_search_metadata(table, model_name) }
  end

  def down
    TABLES.each_key do |table|
      remove_index table, name: overlap_index_name(table)
      remove_column table, :search_embedding_input_tokens
      remove_column table, :search_embedding_scope
      remove_column table, :search_embedding_input_hash
      remove_column table, :search_embedding_model
      remove_column table, :search_content_hash
      remove_column table, :search_synced_at
      remove_column table, :search_index_sequence
      remove_column table, :search_revision
    end
  end

  private

  def add_search_columns(table)
    add_column table, :search_revision, :integer, null: false, default: 0
    add_column table, :search_index_sequence, :bigint
    add_column table, :search_synced_at, :timestamptz
    add_column table, :search_content_hash, :string
    add_column table, :search_embedding_model, :string
    add_column table, :search_embedding_input_hash, :string
    add_column table, :search_embedding_scope, :string
    add_column table, :search_embedding_input_tokens, :integer
    add_index table, [ :search_synced_at, :search_index_sequence ],
      name: overlap_index_name(table)
  end

  def backfill_search_metadata(table, model_name)
    execute <<~SQL.squish
      UPDATE #{table} AS source
      SET search_revision = document.revision,
          search_index_sequence = NULL,
          search_synced_at = NULL,
          search_content_hash = document.content_hash,
          search_embedding_model = document.embedding_model,
          search_embedding_input_hash = document.embedding_input_hash,
          search_embedding_scope = document.embedding_scope,
          search_embedding_input_tokens = document.embedding_input_tokens
      FROM public.search_documents AS document
      WHERE document.source_record_type = #{connection.quote(model_name)}
        AND document.source_record_id = source.id
    SQL
  end

  def overlap_index_name(table)
    "idx_#{table.split('.').last}_search_sync"
  end
end
