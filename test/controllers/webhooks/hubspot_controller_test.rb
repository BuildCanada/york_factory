require "test_helper"

class Webhooks::HubspotControllerTest < ActionDispatch::IntegrationTest
  test "handles contact property change events" do
    event_payload = [
      {
        "subscriptionType" => "contact.propertyChange",
        "objectId" => "12345",
        "propertyName" => "email",
        "propertyValue" => "new-email@example.com"
      }
    ]

    assert_enqueued_with(job: HubspotContactSyncFromWebhookJob, args: [ "12345", event_payload.first ]) do
      post webhooks_hubspot_index_url,
        params: event_payload.to_json,
        headers: { "Content-Type" => "application/json" }
    end

    assert_response :success
  end

  test "handles contact creation events" do
    event_payload = [
      {
        "subscriptionType" => "contact.creation",
        "objectId" => "54321"
      }
    ]

    assert_enqueued_with(job: HubspotContactSyncFromWebhookJob, args: [ "54321", event_payload.first ]) do
      post webhooks_hubspot_index_url,
        params: event_payload.to_json,
        headers: { "Content-Type" => "application/json" }
    end

    assert_response :success
  end

  test "handles contact deletion events" do
    contact = hubspot_contacts(:one)

    event_payload = [
      {
        "subscriptionType" => "contact.deletion",
        "objectId" => contact.hubspot_contact_id
      }
    ]

    assert_difference("HubspotContact.count", -1) do
      post webhooks_hubspot_index_url,
        params: event_payload.to_json,
        headers: { "Content-Type" => "application/json" }
    end

    assert_response :success
  end

  test "skips unimportant property changes" do
    event_payload = [
      {
        "subscriptionType" => "contact.propertyChange",
        "objectId" => "12345",
        "propertyName" => "hs_analytics_last_timestamp",
        "propertyValue" => "1735732800000"
      }
    ]

    assert_no_enqueued_jobs(only: HubspotContactSyncFromWebhookJob) do
      post webhooks_hubspot_index_url,
        params: event_payload.to_json,
        headers: { "Content-Type" => "application/json" }
    end

    assert_response :success
  end

  test "handles unknown event types" do
    event_payload = [
      {
        "subscriptionType" => "unknown.event",
        "objectId" => "12345"
      }
    ]

    post webhooks_hubspot_index_url,
      params: event_payload.to_json,
      headers: { "Content-Type" => "application/json" }

    assert_response :success
  end
end
