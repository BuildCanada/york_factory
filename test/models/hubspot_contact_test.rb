require "test_helper"

class HubspotContactTest < ActiveSupport::TestCase
  # Disable fixtures to avoid conflicts
  self.use_transactional_tests = true

  setup do
    # Clean up any existing data
    HubspotContact.delete_all
  end
  test "creates contact from hubspot properties" do
    properties = {
      "hs_object_id" => "12345",
      "email" => "test@example.com",
      "firstname" => "John",
      "lastname" => "Doe",
      "phone" => "+1234567890",
      "company" => "Test Corp",
      "createdate" => "2025-01-01T00:00:00Z"
    }

    contact = HubspotContact.from_hubspot_properties(properties)

    assert_equal "12345", contact.hubspot_contact_id
    assert_equal "test@example.com", contact.email
    assert_equal "John", contact.firstname
    assert_equal "Doe", contact.lastname
    assert_equal "+1234567890", contact.phone
    assert_equal "Test Corp", contact.company
  end

  test "validates required fields" do
    contact = HubspotContact.new
    assert_not contact.valid?
    assert_includes contact.errors[:email], "can't be blank"
  end

  test "validates email format" do
    contact = HubspotContact.new(
      hubspot_contact_id: "12345",
      email: "invalid-email"
    )
    assert_not contact.valid?
    assert_includes contact.errors[:email], "must be a valid email address"
  end

  test "full_name returns combined first and last name" do
    contact = HubspotContact.new(firstname: "John", lastname: "Doe")
    assert_equal "John Doe", contact.full_name
  end

  test "parses hubspot timestamps" do
    # Test ISO 8601 format
    iso_timestamp = "2025-01-01T12:00:00Z"
    result = HubspotContact.new.parse_hubspot_timestamp(iso_timestamp)
    assert_equal Time.parse(iso_timestamp), result

    # Test milliseconds format
    ms_timestamp = "1735732800000"
    result = HubspotContact.new.parse_hubspot_timestamp(ms_timestamp)
    assert_equal Time.at(1735732800), result
  end

  test "handles invalid timestamps gracefully" do
    result = HubspotContact.new.parse_hubspot_timestamp("invalid")
    assert_nil result
  end
end
