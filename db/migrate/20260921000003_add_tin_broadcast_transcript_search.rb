class AddTinBroadcastTranscriptSearch < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    enable_extension "tin" unless extension_enabled?("tin")

    execute <<~SQL
      CREATE INDEX CONCURRENTLY idx_media_passages_tin_text
      ON warehouse.media_transcript_passages USING tin (text)
      WHERE state = 'published'
    SQL
  end

  def down
    execute "DROP INDEX CONCURRENTLY IF EXISTS warehouse.idx_media_passages_tin_text"
  end
end
