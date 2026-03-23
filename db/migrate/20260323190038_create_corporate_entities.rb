class CreateCorporateEntities < ActiveRecord::Migration[8.1]
  def change
    create_table :corporate_entities do |t|
      t.string :jurisdiction, null: false
      t.string :registry_id, null: false
      t.string :business_number
      t.string :legal_name, null: false
      t.string :corporation_type
      t.string :status
      t.string :governing_act
      t.string :registered_office_address
      t.string :registered_office_province
      t.string :registered_office_postal_code
      t.date :incorporation_date
      t.date :dissolution_date
      t.string :business_activity
      t.string :source_system
      t.jsonb :raw_data, default: {}
      t.references :government_entity, foreign_key: true, null: true
      t.references :raw_ingestion, foreign_key: true, null: true
      t.boolean :enriched, default: false
      t.datetime :enriched_at
      t.boolean :needs_review, default: false
      t.timestamps
    end

    add_index :corporate_entities, [:jurisdiction, :registry_id], unique: true
    add_index :corporate_entities, :business_number
    add_index :corporate_entities, :legal_name
    add_index :corporate_entities, :status
    add_index :corporate_entities, :jurisdiction
    add_index :corporate_entities, :registered_office_province
    add_index :corporate_entities, :enriched
    add_index :corporate_entities, :needs_review
    add_index :corporate_entities, :source_system
    add_index :corporate_entities, :legal_name, using: :gin, opclass: :gin_trgm_ops,
      name: "idx_corp_entities_legal_name_trgm"
  end
end
