class CreateCorporateRegistrations < ActiveRecord::Migration[8.1]
  def change
    create_table :corporate_registrations do |t|
      t.references :corporate_entity, null: false, foreign_key: true
      t.string :event_type, null: false
      t.date :event_date
      t.text :description
      t.jsonb :details, default: {}
      t.timestamps
    end

    add_index :corporate_registrations, [:corporate_entity_id, :event_type, :event_date],
      name: "idx_registrations_entity_event"
  end
end
