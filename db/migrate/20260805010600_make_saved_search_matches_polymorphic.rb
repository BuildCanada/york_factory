class MakeSavedSearchMatchesPolymorphic < ActiveRecord::Migration[8.1]
  def up
    add_column :saved_search_matches, :searchable_type, :string
    add_column :saved_search_matches, :searchable_id, :string
    add_index :saved_search_matches, [ :searchable_type, :searchable_id ]

    execute <<~SQL.squish
      UPDATE saved_search_matches AS matches
      SET searchable_type = CASE
            WHEN documents.realm = 'media' THEN 'Search::MediaArticle'
            ELSE documents.source_record_type
          END,
          searchable_id = CASE
            WHEN documents.realm = 'media' THEN documents.id::text
            ELSE documents.source_record_id::text
          END
      FROM search_documents AS documents
      WHERE documents.id = matches.search_document_id
    SQL

    change_column_null :saved_search_matches, :searchable_type, false
    change_column_null :saved_search_matches, :searchable_id, false
    remove_reference :saved_search_matches, :search_document, type: :uuid, foreign_key: true
  end

  def down
    add_reference :saved_search_matches, :search_document, type: :uuid, foreign_key: true

    execute <<~SQL.squish
      UPDATE saved_search_matches AS matches
      SET search_document_id = documents.id
      FROM search_documents AS documents
      WHERE (matches.searchable_type = 'Search::MediaArticle' AND documents.id::text = matches.searchable_id)
         OR (documents.source_record_type = matches.searchable_type AND documents.source_record_id::text = matches.searchable_id)
    SQL

    change_column_null :saved_search_matches, :search_document_id, false
    remove_index :saved_search_matches, [ :searchable_type, :searchable_id ]
    remove_column :saved_search_matches, :searchable_id
    remove_column :saved_search_matches, :searchable_type
  end
end
