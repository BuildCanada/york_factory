require "test_helper"

class Search::DeliverNotificationJobTest < ActiveJob::TestCase
  FakeResponse = Struct.new(:status, :headers) do
    def [](name)
      headers[name]
    end
  end

  class FakeHttp
    attr_reader :requests

    def initialize(response)
      @response = response
      @requests = []
    end

    def post(url, **options)
      requests << { url: url, **options }
      @response
    end
  end

  setup do
    feed = Warehouse::MediaFeed.create!(
      name: "Webhook feed #{SecureRandom.hex(4)}",
      strategy: "rss",
      url: "https://nationalpost.com/feed/",
      cadence_seconds: 300,
      publisher_name: "National Post",
      publisher_domain: "nationalpost.com",
      language: "en"
    )
    article = Warehouse::MediaArticle.new(
      feed:,
      external_key: SecureRandom.uuid,
      title: "Webhook article",
      content: "Body",
      language: "en",
      realm_data: {
        "content_type" => "article",
        "publisher_name" => "National Post",
        "publisher_domain" => "nationalpost.com",
        "authors" => [],
        "word_count" => 1
      }
    )
    article.publish!
    @saved_search = SavedSearch.create!(
      user: users(:member),
      name: "Webhook alerts #{SecureRandom.hex(4)}",
      realm: "media",
      definition: { version: 1, realm: "media", mode: "filter_only" },
      delivery_mode: "instant",
      delivery_configuration: {
        channels: [ "webhook" ],
        webhook_url: "https://hooks.example.com/search"
      }
    )
    match = @saved_search.matches.create!(searchable: article, state: "buffered")
    @batch = @saved_search.notification_batches.create!(
      mode: "instant",
      scheduled_for: Time.current
    )
    match.update!(notification_batch: @batch)
    @batch.close!
    @delivery = @batch.notification_deliveries.find_by!(channel: "webhook")
    clear_enqueued_jobs
  end

  test "posts a signed JSON payload through HTTPX" do
    response = FakeResponse.new(202, { "x-request-id" => "request-123" })
    http = FakeHttp.new(response)

    job(http).perform(@delivery.id)

    request = http.requests.fetch(0)
    assert_equal "https://hooks.example.com/search", request[:url]
    assert_equal @batch.payload, JSON.parse(request[:body])
    assert_equal "application/json", request.dig(:headers, "Content-Type")
    assert_equal @delivery.idempotency_key,
      request.dig(:headers, "X-BuildCanada-Delivery")

    timestamp = request.dig(:headers, "X-BuildCanada-Timestamp")
    expected_signature = OpenSSL::HMAC.hexdigest(
      "SHA256",
      @saved_search.webhook_secret,
      "#{timestamp}.#{request[:body]}"
    )
    assert_equal "v1=#{expected_signature}",
      request.dig(:headers, "X-BuildCanada-Signature")
    assert_equal "delivered", @delivery.reload.status
    assert_equal({ "status" => 202, "request_id" => "request-123" }, @delivery.provider_response)
    assert_equal "delivered", @batch.reload.state
  end

  test "retries a transient HTTP response" do
    http = FakeHttp.new(FakeResponse.new(503, {}))

    assert_enqueued_jobs 1, only: Search::DeliverNotificationJob do
      job(http).perform(@delivery.id)
    end

    assert_equal "failed", @delivery.reload.status
    assert_match "webhook returned HTTP 503", @delivery.last_error
    assert @delivery.next_attempt_at.future?
    assert_equal "delivering", @batch.reload.state
  end

  test "marks a permanent HTTP response dead" do
    http = FakeHttp.new(FakeResponse.new(400, {}))

    assert_no_enqueued_jobs only: Search::DeliverNotificationJob do
      job(http).perform(@delivery.id)
    end

    assert_equal "dead", @delivery.reload.status
    assert_match "webhook returned HTTP 400", @delivery.last_error
    assert_equal "dead", @batch.reload.state
  end

  private

  def job(http)
    Search::DeliverNotificationJob.new.tap do |job|
      job.instance_variable_set(:@webhook_http, http)
      job.define_singleton_method(:validate_webhook_url) { |url| url }
    end
  end
end
