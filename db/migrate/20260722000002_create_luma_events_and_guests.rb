class CreateLumaEventsAndGuests < ActiveRecord::Migration[8.1]
  def change
    create_table :luma_events do |t|
      t.string :luma_event_id, null: false
      t.text :name
      t.text :description
      t.datetime :start_at
      t.datetime :end_at
      t.string :timezone
      t.string :visibility
      t.string :url
      t.string :location_name
      t.text :location_address
      t.datetime :created_at_luma
      t.datetime :updated_at_luma
      t.jsonb :event_data, default: {}
      t.datetime :last_synced_at
      t.datetime :hubspot_synced_at

      t.timestamps
    end

    add_index :luma_events, :luma_event_id, unique: true
    add_index :luma_events, :start_at
    add_index :luma_events, :visibility
    add_index :luma_events, :last_synced_at

    create_table :luma_event_guests do |t|
      t.references :luma_event, null: false, foreign_key: true
      t.string :luma_user_id, null: false
      t.string :name
      t.string :email
      t.string :approval_status
      t.boolean :checked_in, default: false
      t.datetime :checked_in_at
      t.datetime :registered_at
      t.jsonb :guest_data, default: {}
      t.datetime :last_synced_at

      t.timestamps
    end

    add_index :luma_event_guests, [ :luma_event_id, :luma_user_id ], unique: true
    add_index :luma_event_guests, :luma_user_id
    add_index :luma_event_guests, :email
    add_index :luma_event_guests, :approval_status
    add_index :luma_event_guests, :checked_in
    add_index :luma_event_guests, :last_synced_at
  end
end
