require "test_helper"

class CustomerioServiceTest < ActiveSupport::TestCase
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

  test "identify_subscriber posts the subscriber's traits keyed by row id" do
    captured_url = captured_payload = captured_headers = nil
    HTTP.define_singleton_method(:post) do |url, json:, headers:|
      captured_url = url
      captured_payload = json
      captured_headers = headers
      FakeResponse.new(success: true)
    end

    subscriber = subscribers(:existing_subscriber)
    service = CustomerioService.new(api_key: "write-key")
    assert service.identify_subscriber(subscriber)

    assert_equal CustomerioService::IDENTIFY_URL, captured_url
    assert_equal subscriber.id.to_s, captured_payload[:userId]
    traits = captured_payload[:traits]
    assert_equal "test@example.com", traits[:email]
    assert_equal "Test", traits[:first_name]
    assert_equal "User", traits[:last_name]
    assert_equal "Test User", traits[:name]
    assert_equal "K1A 0A6", traits[:postal_code]
    assert_equal true, traits[:newsletter_opt_in]

    # Basic auth sends the write key as the username with an empty password.
    assert_equal "Basic #{Base64.strict_encode64("write-key:")}", captured_headers["Authorization"]
  ensure
    HTTP.singleton_class.remove_method(:post)
  end

  test "identify_subscriber omits blank traits but always sends the opt-in state" do
    captured_payload = nil
    HTTP.define_singleton_method(:post) do |_url, json:, headers:|
      captured_payload = json
      FakeResponse.new(success: true)
    end

    subscriber = Subscriber.create!(email: "bare@example.com")
    CustomerioService.new(api_key: "write-key").identify_subscriber(subscriber)

    traits = captured_payload[:traits]
    assert_equal "bare@example.com", traits[:email]
    assert_not traits.key?(:first_name)
    assert_not traits.key?(:postal_code)
    assert_equal false, traits[:newsletter_opt_in]
  ensure
    HTTP.singleton_class.remove_method(:post)
  end

  test "identify_subscriber raises on a failed identify so the job retries" do
    HTTP.define_singleton_method(:post) { |_url, json:, headers:| FakeResponse.new(success: false) }

    assert_raises CustomerioService::IdentifyError do
      CustomerioService.new(api_key: "write-key").identify_subscriber(subscribers(:existing_subscriber))
    end
  ensure
    HTTP.singleton_class.remove_method(:post)
  end

  test "identify_subscriber raises when no API key is configured" do
    assert_raises CustomerioService::ConfigurationError do
      CustomerioService.new(api_key: nil).identify_subscriber(subscribers(:existing_subscriber))
    end
  end

  test "identify_subscriber raises rather than keying a person off a blank id" do
    assert_raises CustomerioService::IdentifyError do
      CustomerioService.new(api_key: "write-key").identify_subscriber(Subscriber.new(email: "unsaved@example.com"))
    end
  end
end
