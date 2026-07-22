require "test_helper"

class HubspotEventsServiceTest < ActiveSupport::TestCase
  def setup
    @luma_event = luma_events(:upcoming_event)
  end

  test "upsert_event upserts the marketing event, stamps hubspot_synced_at, and creates lists" do
    upsert_calls = []
    list_event_ids = []

    fake_response = Object.new
    fake_response.define_singleton_method(:object_id) { "999" }

    fake_client = build_fake_client do |external_event_id:, body:|
      upsert_calls << [ external_event_id, body ]
      fake_response
    end

    Hubspot::Client.define_singleton_method(:new) { |**_| fake_client }

    service = HubspotEventsService.new
    service.define_singleton_method(:create_event_lists) do |_event, hubspot_event_id = nil|
      list_event_ids << hubspot_event_id
    end

    service.upsert_event(@luma_event, sync_guests: false)

    assert_equal 1, upsert_calls.size
    external_event_id, body = upsert_calls.first
    assert_equal "luma-#{@luma_event.luma_event_id}", external_event_id
    assert_equal @luma_event.name, body[:eventName]
    assert_equal "Luma Event", body[:eventType]
    assert_equal false, body[:eventCompleted]
    assert_equal [ "342054223-0-54-999" ], list_event_ids
    assert @luma_event.reload.hubspot_synced_at.present?
  ensure
    Hubspot::Client.singleton_class.remove_method(:new)
  end

  test "upsert_event raises on API errors" do
    fake_client = build_fake_client do |**_|
      raise StandardError, "API Error"
    end

    Hubspot::Client.define_singleton_method(:new) { |**_| fake_client }

    service = HubspotEventsService.new

    assert_raises(StandardError) do
      service.upsert_event(@luma_event)
    end
  ensure
    Hubspot::Client.singleton_class.remove_method(:new)
  end

  test "build_event_body builds the marketing event payload" do
    service = build_service_with_null_client
    body = service.send(:build_event_body, @luma_event)

    assert_equal @luma_event.start_at.iso8601, body[:startDateTime]
    assert_equal @luma_event.end_at.iso8601, body[:endDateTime]
    assert_equal @luma_event.name, body[:eventName]
    assert_equal @luma_event.url, body[:eventUrl]
    assert_equal "Luma Event", body[:eventType]
    assert_equal "Build Canada", body[:eventOrganizer]
    assert_equal "luma-#{@luma_event.luma_event_id}", body[:externalEventId]
    assert_equal "luma", body[:externalAccountId]
  end

  test "build_custom_properties includes relevant event data" do
    service = build_service_with_null_client
    properties = service.send(:build_custom_properties, @luma_event)

    property_names = properties.map { |p| p[:name] }
    assert_includes property_names, "location_name"
    assert_includes property_names, "location_address"
    assert_includes property_names, "timezone"
    assert_includes property_names, "visibility"
    assert_includes property_names, "duration_hours"
  end

  private

  # Fake for the client.marketing.events.basic_api.upsert chain
  def build_fake_client(&upsert)
    basic_api = Object.new
    basic_api.define_singleton_method(:upsert, &upsert)
    events_api = Object.new
    events_api.define_singleton_method(:basic_api) { basic_api }
    marketing_api = Object.new
    marketing_api.define_singleton_method(:events) { events_api }
    client = Object.new
    client.define_singleton_method(:marketing) { marketing_api }
    client
  end

  def build_service_with_null_client
    Hubspot::Client.define_singleton_method(:new) { |**_| Object.new }
    HubspotEventsService.new
  ensure
    Hubspot::Client.singleton_class.remove_method(:new)
  end
end
