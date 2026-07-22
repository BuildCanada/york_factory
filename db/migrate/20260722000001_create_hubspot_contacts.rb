class CreateHubspotContacts < ActiveRecord::Migration[8.1]
  def change
    create_table :hubspot_contacts do |t|
      t.string :hubspot_contact_id
      t.string :email
      t.string :firstname
      t.string :lastname
      t.string :phone
      t.string :company
      t.string :city
      t.string :country
      t.string :website
      t.text :background
      t.string :linkedin_url
      t.string :bluesky_handle
      t.string :twitter_handle
      t.datetime :create_date
      t.datetime :last_activity_date
      t.boolean :email_confirmed
      t.jsonb :raw_properties
      t.datetime :synced_at
      t.string :member_source
      t.datetime :joined_at
      t.string :provincial_constituency
      t.string :federal_constituency
      t.string :zip
      t.string :hs_state_code
      t.string :state
      t.string :hs_marketable_status
      t.datetime :discord_join_date
      t.boolean :is_member
      t.string :discord_username
      t.text :whatsapp_groups
      t.text :twitter_subscriptions
      t.text :substack_subscriptions
      t.integer :num_unique_conversion_events
      t.string :first_conversion_event_name
      t.boolean :role
      t.string :message
      t.string :industry
      t.string :jobtitle
      t.boolean :house_rules
      t.string :full_name
      t.string :interests
      t.string :skillsets
      t.string :ip_country
      t.string :ip_city
      t.string :ip_state
      t.string :the_basics
      t.string :hs_timezone
      t.string :time_commitment
      t.string :substack_handle
      t.string :hs_latest_source
      t.string :associatedcompanyid
      t.string :profession
      t.text :skills
      t.text :work_interest
      t.text :about_accomplishments
      t.boolean :non_partisan_agreement
      t.string :postal_code
      t.string :province
      t.string :country_code
      t.decimal :latitude, precision: 10, scale: 7
      t.decimal :longitude, precision: 10, scale: 7
      t.string :timezone
      t.jsonb :raw_constituencies
      t.boolean :newsletter_subscription, default: true
      t.datetime :hs_createdate
      t.string :hs_object_source_label
      t.string :hs_object_source_detail_1
      t.datetime :member_join_date
      t.text :discord_display_name

      t.timestamps
    end

    add_index :hubspot_contacts, :email
    add_index :hubspot_contacts, :full_name
    add_index :hubspot_contacts, :hs_latest_source
    add_index :hubspot_contacts, :hubspot_contact_id, unique: true
    add_index :hubspot_contacts, :postal_code
    add_index :hubspot_contacts, :synced_at
  end
end
