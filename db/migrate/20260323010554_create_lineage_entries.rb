class CreateLineageEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :lineage_entries do |t|
      t.references :raw_ingestion, foreign_key: true
      t.string :source_field
      t.string :source_value
      t.string :target_field
      t.string :target_value
      t.string :transformation_type, null: false
      t.string :llm_model
      t.jsonb :llm_prompt_snapshot
      t.jsonb :llm_response_snapshot
      t.decimal :confidence, precision: 5, scale: 4
      t.boolean :human_override, default: false
      t.string :override_by
      t.datetime :override_at

      t.timestamps
    end
  end
end
