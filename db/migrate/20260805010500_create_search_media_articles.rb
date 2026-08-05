class CreateSearchMediaArticles < ActiveRecord::Migration[8.1]
  def up
    create_table :search_media_articles, id: :uuid do |t|
      t.references :search_source, foreign_key: true
      t.string :external_key
      t.string :state, null: false, default: "draft"
      t.string :visibility, null: false, default: "public"
      t.uuid :permission_ids, array: true, null: false, default: []
      t.integer :search_revision, null: false, default: 0
      t.bigint :search_index_sequence
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
      t.string :search_content_hash
      t.jsonb :ontology, null: false, default: {}
      t.jsonb :realm_data, null: false, default: {}
      t.string :search_embedding_model
      t.string :search_embedding_input_hash
      t.string :search_embedding_scope
      t.integer :search_embedding_input_tokens
      t.jsonb :extraction_metadata, null: false, default: {}
      t.jsonb :validation_errors, null: false, default: []
      t.timestamps
    end

    add_index :search_media_articles, [ :search_source_id, :external_key ],
      unique: true,
      where: "search_source_id IS NOT NULL AND external_key IS NOT NULL",
      name: "idx_search_media_articles_source_key"
    add_index :search_media_articles, :canonical_url_digest,
      unique: true,
      where: "canonical_url_digest IS NOT NULL",
      name: "idx_search_media_articles_canonical_url"
    add_index :search_media_articles, :state
    add_index :search_media_articles, :search_index_sequence
    add_index :search_media_articles, [ :search_synced_at, :search_index_sequence ],
      name: "idx_search_media_articles_sync_overlap"
    add_check_constraint :search_media_articles,
      "state IN ('draft','published','withdrawn','invalid')",
      name: "search_media_articles_state"
    add_check_constraint :search_media_articles, "search_revision >= 0",
      name: "search_media_articles_revision_nonnegative"
    add_check_constraint :search_media_articles,
      "search_embedding_scope IS NULL OR search_embedding_scope IN ('full','truncated')",
      name: "search_media_articles_embedding_scope"

    backfill_existing_media_documents
  end

  def down
    drop_table :search_media_articles
  end

  private

  def backfill_existing_media_documents
    return unless table_exists?(:search_documents)

    execute <<~SQL.squish
      INSERT INTO search_media_articles (
        id, search_source_id, external_key, state, visibility, permission_ids,
        search_revision, search_index_sequence, search_synced_at, canonical_url,
        canonical_url_digest, source_url, title, summary, content, language,
        published_at, source_updated_at, first_seen_at, last_seen_at,
        search_content_hash, ontology, realm_data, search_embedding_model,
        search_embedding_input_hash, search_embedding_scope, search_embedding_input_tokens,
        extraction_metadata, validation_errors, created_at, updated_at
      )
      SELECT
        id, search_source_id, external_key, state, visibility, permission_ids,
        revision, NULL, NULL, canonical_url,
        canonical_url_digest, source_url, title, summary, content, language,
        published_at, source_updated_at, first_seen_at, last_seen_at,
        content_hash, ontology, realm_data, embedding_model,
        embedding_input_hash, embedding_scope, embedding_input_tokens,
        extraction_metadata, validation_errors, created_at, updated_at
      FROM search_documents
      WHERE realm = 'media'
    SQL
  end
end
