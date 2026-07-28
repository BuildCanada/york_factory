require "test_helper"

class HubspotFormsServiceTest < ActiveSupport::TestCase
  # Stands in for an HTTP::Response: `status` returns self so that
  # `response.status.success?` works.
  class FakeResponse
    def initialize(success:)
      @success = success
    end

    def status = self
    def success? = @success
    def body = "response body"
  end

  test "submit_subscriber posts the subscriber's fields and tracking context to the form endpoint" do
    captured_url = captured_payload = nil
    HTTP.define_singleton_method(:post) do |url, json:|
      captured_url = url
      captured_payload = json
      FakeResponse.new(success: true)
    end

    subscriber = Subscriber.new(
      email: "voter@example.com", first_name: "Jane", last_name: "Voter", postal_code: "M5V 1A1",
      source: "pledge", hubspot_utk: "utk-cookie", ip_address: "203.0.113.7",
      page_uri: "https://buildcanada.com/elections/toronto-2026", page_name: "Toronto 2026"
    )

    service = HubspotFormsService.new(portal_id: "123456", form_guid: "form-guid")
    assert service.submit_subscriber(subscriber)

    assert_equal "#{HubspotFormsService::SUBMIT_URL}/123456/form-guid", captured_url
    expected_fields = [
      { objectTypeId: "0-1", name: "email", value: "voter@example.com" },
      { objectTypeId: "0-1", name: "firstname", value: "Jane" },
      { objectTypeId: "0-1", name: "lastname", value: "Voter" },
      { objectTypeId: "0-1", name: "zip", value: "M5V 1A1" },
      { objectTypeId: "0-1", name: "member_source", value: "pledge" }
    ]
    assert_equal expected_fields, captured_payload[:fields]
    expected_context = {
      hutk: "utk-cookie",
      pageUri: "https://buildcanada.com/elections/toronto-2026",
      pageName: "Toronto 2026",
      ipAddress: "203.0.113.7"
    }
    assert_equal expected_context, captured_payload[:context]
  ensure
    HTTP.singleton_class.remove_method(:post)
  end

  test "submit_subscriber omits blank fields and skips the context block when empty" do
    captured_payload = nil
    HTTP.define_singleton_method(:post) do |_url, json:|
      captured_payload = json
      FakeResponse.new(success: true)
    end

    service = HubspotFormsService.new(portal_id: "123456", form_guid: "form-guid")
    service.submit_subscriber(Subscriber.new(email: "bare@example.com"))

    assert_equal [ { objectTypeId: "0-1", name: "email", value: "bare@example.com" } ],
      captured_payload[:fields]
    assert_not captured_payload.key?(:context)
  ensure
    HTTP.singleton_class.remove_method(:post)
  end

  test "submit_subscriber raises on a failed submission so the job retries" do
    HTTP.define_singleton_method(:post) { |_url, json:| FakeResponse.new(success: false) }

    service = HubspotFormsService.new(portal_id: "123456", form_guid: "form-guid")

    assert_raises(HubspotFormsService::SubmissionError) do
      service.submit_subscriber(subscribers(:existing_subscriber))
    end
  ensure
    HTTP.singleton_class.remove_method(:post)
  end

  test "submit_subscriber is a no-op in development unless ENABLE_HUBSPOT_SUBMISSIONS is set" do
    posted = false
    HTTP.define_singleton_method(:post) { |*, **| posted = true; FakeResponse.new(success: true) }
    original_env = Rails.method(:env)
    Rails.define_singleton_method(:env) { ActiveSupport::StringInquirer.new("development") }

    service = HubspotFormsService.new(portal_id: "123456", form_guid: "form-guid")
    assert_equal false, service.submit_subscriber(subscribers(:existing_subscriber))
    assert_not posted

    ENV["ENABLE_HUBSPOT_SUBMISSIONS"] = "1"
    assert service.submit_subscriber(subscribers(:existing_subscriber))
    assert posted
  ensure
    ENV.delete("ENABLE_HUBSPOT_SUBMISSIONS")
    Rails.define_singleton_method(:env, original_env) if original_env
    HTTP.singleton_class.remove_method(:post)
  end

  test "submit_subscriber raises when the form GUID or portal ID is not configured" do
    assert_raises(HubspotFormsService::ConfigurationError) do
      HubspotFormsService.new(portal_id: "123456", form_guid: nil)
        .submit_subscriber(subscribers(:existing_subscriber))
    end

    assert_raises(HubspotFormsService::ConfigurationError) do
      HubspotFormsService.new(portal_id: nil, form_guid: "form-guid")
        .submit_subscriber(subscribers(:existing_subscriber))
    end
  end
end
