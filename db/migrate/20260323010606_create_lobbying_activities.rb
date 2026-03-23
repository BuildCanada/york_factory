class CreateLobbyingActivities < ActiveRecord::Migration[8.1]
  def change
    create_table :lobbying_activities do |t|
      t.references :lobbyist, null: false, foreign_key: true
      t.references :organization, foreign_key: true
      t.string :client_name
      t.string :subject_matter
      t.date :start_date
      t.date :end_date
      t.string :status
      t.references :raw_ingestion, foreign_key: true
      t.references :lineage_entry, foreign_key: { to_table: :lineage_entries }

      t.timestamps
    end
  end
end
