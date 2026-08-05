class DropSearchDocuments < ActiveRecord::Migration[8.1]
  def up
    drop_table :search_documents
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
      "search documents were replaced by source-owned searchable records"
  end
end
