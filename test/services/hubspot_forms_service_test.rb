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

  test "submit_subscriber posts the subscriber's fields to the form endpoint" do
    captured_url = captured_payload = nil
    HTTP.define_singleton_method(:post) do |url, json:|
      captured_url = url
      captured_payload = json
      FakeResponse.new(success: true)
    end

    service = HubspotFormsService.new(portal_id: "123456", form_guid: "form-guid")
    assert service.submit_subscriber(subscribers(:existing_subscriber))

    assert_equal "#{HubspotFormsService::SUBMIT_URL}/123456/form-guid", captured_url
    expected_fields = [
      { objectTypeId: "0-1", name: "email", value: "test@example.com" },
      { objectTypeId: "0-1", name: "firstname", value: "Test" },
      { objectTypeId: "0-1", name: "lastname", value: "User" },
      { objectTypeId: "0-1", name: "zip", value: "K1A 0A6" }
    ]
    assert_equal expected_fields, captured_payload[:fields]
  ensure
    HTTP.singleton_class.remove_method(:post)
  end

  test "submit_subscriber omits blank fields" do
    captured_payload = nil
    HTTP.define_singleton_method(:post) do |_url, json:|
      captured_payload = json
      FakeResponse.new(success: true)
    end

    service = HubspotFormsService.new(portal_id: "123456", form_guid: "form-guid")
    service.submit_subscriber(Subscriber.new(email: "bare@example.com"))

    assert_equal [ { objectTypeId: "0-1", name: "email", value: "bare@example.com" } ],
      captured_payload[:fields]
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

  test "submit_subscriber raises when no form GUID is configured" do
    service = HubspotFormsService.new(portal_id: "123456", form_guid: nil)

    assert_raises(HubspotFormsService::ConfigurationError) do
      service.submit_subscriber(subscribers(:existing_subscriber))
    end
  end
end
