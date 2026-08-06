class MoveMediaRecordsToWarehouse < ActiveRecord::Migration[8.1]
  def up
    incompatible_count = select_value(<<~SQL.squish).to_i
      SELECT COUNT(*) FROM search_sources
      WHERE realm <> 'media' OR strategy NOT IN ('rss', 'atom')
    SQL
    if incompatible_count.positive?
      raise ActiveRecord::MigrationError,
        "search_sources contains #{incompatible_count} non-media-feed rows; migrate them before renaming the table"
    end

    rename_table :search_sources, :media_feeds
    rename_table :search_source_fetches, :media_feed_fetches
    rename_table :search_media_articles, :media_articles
    rename_column :media_feed_fetches, :search_source_id, :media_feed_id
    rename_column :media_articles, :search_source_id, :media_feed_id

    add_column :media_feeds, :publisher_name, :string
    add_column :media_feeds, :publisher_domain, :string
    add_column :media_feeds, :language, :string, default: "en", null: false
    add_column :media_feeds, :fallback_url, :text
    add_column :media_feeds, :allow_http, :boolean, default: false, null: false

    execute <<~SQL.squish
      UPDATE media_feeds
      SET publisher_name = COALESCE(configuration->>'publisher_name', name),
          publisher_domain = COALESCE(
            configuration->>'publisher_domain',
            lower(substring(url from '^https?://(?:www\\.)?([^/:?]+)'))
          ),
          language = COALESCE(configuration->>'language', 'en'),
          fallback_url = configuration->>'fallback_url',
          allow_http = COALESCE((configuration->>'allow_http')::boolean, false)
    SQL

    change_column_null :media_feeds, :publisher_name, false
    change_column_null :media_feeds, :publisher_domain, false
    remove_column :media_feeds, :realm
    remove_column :media_feeds, :configuration

    rename_database_objects_to_media_feeds
    execute <<~SQL.squish
      UPDATE saved_search_matches
      SET searchable_type = 'Warehouse::MediaArticle'
      WHERE searchable_type = 'Search::MediaArticle'
    SQL

    execute "ALTER TABLE media_feeds SET SCHEMA warehouse"
    execute "ALTER TABLE media_feed_fetches SET SCHEMA warehouse"
    execute "ALTER TABLE media_articles SET SCHEMA warehouse"
  end

  def down
    execute "ALTER TABLE warehouse.media_articles SET SCHEMA public"
    execute "ALTER TABLE warehouse.media_feed_fetches SET SCHEMA public"
    execute "ALTER TABLE warehouse.media_feeds SET SCHEMA public"

    execute <<~SQL.squish
      UPDATE saved_search_matches
      SET searchable_type = 'Search::MediaArticle'
      WHERE searchable_type = 'Warehouse::MediaArticle'
    SQL
    rename_database_objects_to_search_sources

    add_column :media_feeds, :realm, :string, default: "media", null: false
    add_column :media_feeds, :configuration, :jsonb, default: {}, null: false
    execute <<~SQL.squish
      UPDATE media_feeds
      SET configuration = jsonb_strip_nulls(jsonb_build_object(
        'publisher_name', publisher_name,
        'publisher_domain', publisher_domain,
        'language', language,
        'fallback_url', fallback_url,
        'allow_http', allow_http
      ))
    SQL
    remove_columns :media_feeds,
      :publisher_name, :publisher_domain, :language, :fallback_url, :allow_http

    rename_column :media_articles, :media_feed_id, :search_source_id
    rename_column :media_feed_fetches, :media_feed_id, :search_source_id
    rename_table :media_articles, :search_media_articles
    rename_table :media_feed_fetches, :search_source_fetches
    rename_table :media_feeds, :search_sources
  end

  private

  def rename_database_objects_to_media_feeds
    rename_index_if_present(:media_feeds, "idx_search_sources_due", "idx_media_feeds_due")
    rename_index_if_present(:media_feeds, "index_search_sources_on_name", "index_media_feeds_on_name")
    rename_index_if_present(:media_feed_fetches, "idx_search_source_fetches_recent", "idx_media_feed_fetches_recent")
    rename_index_if_present(:media_feed_fetches,
      "index_search_source_fetches_on_search_source_id", "index_media_feed_fetches_on_media_feed_id")
    rename_index_if_present(:media_articles,
      "index_search_media_articles_on_search_source_id", "index_media_articles_on_media_feed_id")
    rename_index_if_present(:media_articles,
      "idx_search_media_articles_source_key", "idx_media_articles_media_feed_key")
    rename_index_if_present(:media_articles,
      "idx_search_media_articles_canonical_url", "idx_media_articles_canonical_url")
    rename_index_if_present(:media_articles,
      "idx_search_media_articles_sync_overlap", "idx_media_articles_sync_overlap")

    rename_constraint_if_present(:media_feeds,
      "search_sources_cadence_minimum", "media_feeds_cadence_minimum")
    rename_constraint_if_present(:media_feeds,
      "search_sources_failures_nonnegative", "media_feeds_failures_nonnegative")
    rename_constraint_if_present(:media_feed_fetches,
      "search_source_fetches_status", "media_feed_fetches_status")
    rename_constraint_if_present(:media_articles,
      "search_media_articles_embedding_scope", "media_articles_embedding_scope")
    rename_constraint_if_present(:media_articles,
      "search_media_articles_revision_nonnegative", "media_articles_revision_nonnegative")
    rename_constraint_if_present(:media_articles,
      "search_media_articles_state", "media_articles_state")
  end

  def rename_database_objects_to_search_sources
    rename_index_if_present(:media_feeds, "idx_media_feeds_due", "idx_search_sources_due")
    rename_index_if_present(:media_feeds, "index_media_feeds_on_name", "index_search_sources_on_name")
    rename_index_if_present(:media_feed_fetches, "idx_media_feed_fetches_recent", "idx_search_source_fetches_recent")
    rename_index_if_present(:media_feed_fetches,
      "index_media_feed_fetches_on_media_feed_id", "index_search_source_fetches_on_search_source_id")
    rename_index_if_present(:media_articles,
      "index_media_articles_on_media_feed_id", "index_search_media_articles_on_search_source_id")
    rename_index_if_present(:media_articles,
      "idx_media_articles_media_feed_key", "idx_search_media_articles_source_key")
    rename_index_if_present(:media_articles,
      "idx_media_articles_canonical_url", "idx_search_media_articles_canonical_url")
    rename_index_if_present(:media_articles,
      "idx_media_articles_sync_overlap", "idx_search_media_articles_sync_overlap")

    rename_constraint_if_present(:media_feeds,
      "media_feeds_cadence_minimum", "search_sources_cadence_minimum")
    rename_constraint_if_present(:media_feeds,
      "media_feeds_failures_nonnegative", "search_sources_failures_nonnegative")
    rename_constraint_if_present(:media_feed_fetches,
      "media_feed_fetches_status", "search_source_fetches_status")
    rename_constraint_if_present(:media_articles,
      "media_articles_embedding_scope", "search_media_articles_embedding_scope")
    rename_constraint_if_present(:media_articles,
      "media_articles_revision_nonnegative", "search_media_articles_revision_nonnegative")
    rename_constraint_if_present(:media_articles,
      "media_articles_state", "search_media_articles_state")
  end

  def rename_index_if_present(table, old_name, new_name)
    rename_index(table, old_name, new_name) if index_name_exists?(table, old_name)
  end

  def rename_constraint_if_present(table, old_name, new_name)
    return unless check_constraint_exists?(table, name: old_name)

    execute "ALTER TABLE #{quote_table_name(table)} RENAME CONSTRAINT #{quote_column_name(old_name)} TO #{quote_column_name(new_name)}"
  end
end
