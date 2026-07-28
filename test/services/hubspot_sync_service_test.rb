require "test_helper"

class HubspotSyncServiceTest < ActiveSupport::TestCase
  test "sync_contact_to_hubspot never writes the read-only notes_last_updated property" do
    captured = nil
    fake_basic_api = Object.new
    fake_basic_api.define_singleton_method(:update) do |contact_id:, simple_public_object_input:|
      captured = simple_public_object_input[:properties]
    end
    fake_contacts = Object.new
    fake_contacts.define_singleton_method(:basic_api) { fake_basic_api }
    fake_crm = Object.new
    fake_crm.define_singleton_method(:contacts) { fake_contacts }
    fake_client = Object.new
    fake_client.define_singleton_method(:crm) { fake_crm }
    Hubspot::Client.define_singleton_method(:new) { |**| fake_client }

    # fixture :one has hubspot_contact_id and last_activity_date, which maps
    # to HubSpot's calculated notes_last_updated property
    contact = hubspot_contacts(:one)
    assert contact.last_activity_date.present?

    HubspotSyncService.new.sync_contact_to_hubspot(contact)

    assert captured, "expected an update call to HubSpot"
    assert_not captured.key?("notes_last_updated"),
      "read-only notes_last_updated must not be written (HubSpot rejects it with a 400)"
    assert_equal contact.email, captured["email"]
  ensure
    Hubspot::Client.singleton_class.remove_method(:new)
  end
end
