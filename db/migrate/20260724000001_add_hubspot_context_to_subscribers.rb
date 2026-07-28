class AddHubspotContextToSubscribers < ActiveRecord::Migration[8.1]
  def change
    # Provenance + HubSpot Forms API context, captured at signup and forwarded
    # with the form submission (member_source field, context block).
    add_column :subscribers, :source, :string
    add_column :subscribers, :placement, :string
    add_column :subscribers, :page_uri, :string
    add_column :subscribers, :page_name, :string
    add_column :subscribers, :hubspot_utk, :string
    add_column :subscribers, :ip_address, :string
  end
end
