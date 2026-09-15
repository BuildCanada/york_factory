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
    subscriber.update_columns(city: "Ottawa", province: "Ontario",
      federal_constituency: "Ottawa Centre", provincial_constituency: "Ottawa Centre")
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
    assert_equal "Ottawa", traits[:city]
    assert_equal "Ontario", traits[:province]
    assert_equal "Ottawa Centre", traits[:federal_constituency]
    assert_equal "Ottawa Centre", traits[:provincial_constituency]
    assert_equal true, traits[:newsletter_opt_in]
    assert_equal false, traits[:unsubscribed]
    assert_equal subscriber.created_at.to_i, traits[:created_at]

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
    assert_equal true, traits[:unsubscribed]
  ensure
    HTTP.singleton_class.remove_method(:post)
  end

  # Customer.io acts on `unsubscribed`; `newsletter_opt_in` is a custom flag
  # a campaign has to remember to filter on, so an opt-out has to say both.
  test "an opted-out subscriber is marked unsubscribed" do
    captured_payload = nil
    HTTP.define_singleton_method(:post) do |_url, json:, headers:|
      captured_payload = json
      FakeResponse.new(success: true)
    end

    subscriber = subscribers(:existing_subscriber)
    subscriber.update!(newsletter_opt_in: false)
    CustomerioService.new(api_key: "write-key").identify_subscriber(subscriber)

    assert_equal true, captured_payload[:traits][:unsubscribed]
    assert_equal false, captured_payload[:traits][:newsletter_opt_in]
  ensure
    HTTP.singleton_class.remove_method(:post)
  end

  test "dates are sent as Unix timestamps so date segments can use them" do
    captured_payload = nil
    HTTP.define_singleton_method(:post) do |_url, json:, headers:|
      captured_payload = json
      FakeResponse.new(success: true)
    end

    pledged_at = Time.utc(2026, 7, 29, 12, 0)
    subscriber = subscribers(:existing_subscriber)
    subscriber.update!(pledged_to_vote_at: pledged_at)
    CustomerioService.new(api_key: "write-key").identify_subscriber(subscriber)

    assert_equal pledged_at.to_i, captured_payload[:traits][:pledged_to_vote_at]
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
