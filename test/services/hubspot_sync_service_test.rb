require "test_helper"
require "hubspot/codegen/crm/contacts/api_error"

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
    remove_stubbed_client
  end

  test "turns a HubSpot rate limit into a transient error with its retry delay" do
    api_error = Hubspot::Crm::Contacts::ApiError.new(
      code: 429,
      response_headers: { "Retry-After" => "120" },
      message: "rate limited"
    )
    fake_basic_api = Object.new
    fake_basic_api.define_singleton_method(:update) { |**| raise api_error }
    stub_hubspot_client(fake_basic_api)

    error = assert_raises(TransientError) do
      HubspotSyncService.new.sync_contact_to_hubspot(hubspot_contacts(:one))
    end

    assert_equal 120, error.retry_after
  ensure
    remove_stubbed_client
  end

  test "does not retry a non-transient HubSpot API error" do
    api_error = Hubspot::Crm::Contacts::ApiError.new(code: 400, message: "invalid property")
    fake_basic_api = Object.new
    fake_basic_api.define_singleton_method(:update) { |**| raise api_error }
    stub_hubspot_client(fake_basic_api)

    raised = assert_raises(Hubspot::Crm::Contacts::ApiError) do
      HubspotSyncService.new.sync_contact_to_hubspot(hubspot_contacts(:one))
    end

    assert_same api_error, raised
  ensure
    remove_stubbed_client
  end

  private

  def stub_hubspot_client(fake_basic_api)
    fake_contacts = Object.new
    fake_contacts.define_singleton_method(:basic_api) { fake_basic_api }
    fake_crm = Object.new
    fake_crm.define_singleton_method(:contacts) { fake_contacts }
    fake_client = Object.new
    fake_client.define_singleton_method(:crm) { fake_crm }
    Hubspot::Client.define_singleton_method(:new) { |**| fake_client }
  end

  def remove_stubbed_client
    singleton_class = Hubspot::Client.singleton_class
    singleton_class.remove_method(:new) if singleton_class.instance_methods(false).include?(:new)
  end
end
