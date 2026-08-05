require "test_helper"

class Search::Media::DefuddlerClientTest < ActiveSupport::TestCase
  FakeResponse = Data.define(:status, :body)
  ErrorResponse = Data.define(:error)

  class FakeHttp
    attr_reader :request

    def initialize(response)
      @response = response
    end

    def post(url, **options)
      @request = { url:, **options }
      @response
    end
  end

  test "posts a validated article URL with API key authentication" do
    http = FakeHttp.new(FakeResponse.new(status: 200, body: '{"title":"A title","content":"Body"}'))
    client = Search::Media::DefuddlerClient.new(
      base_url: "https://deffudler.svc.canadasbuilding.com",
      api_key: "secret",
      http: http,
      resolver: ->(_host) { [ "8.8.8.8" ] }
    )

    result = client.convert(url: "https://nationalpost.com/a?utm_source=rss", language: "en")

    assert_equal "A title", result.fetch("title")
    assert_equal "https://deffudler.svc.canadasbuilding.com/api/convert", http.request.fetch(:url)
    assert_equal "secret", http.request.dig(:headers, "X-API-Key")
    assert_equal(
      { "url" => "https://nationalpost.com/a", "language" => "en" },
      JSON.parse(http.request.fetch(:body))
    )
  end

  test "classifies rate limits and server failures as transient" do
    http = FakeHttp.new(FakeResponse.new(status: 429, body: "rate limited"))
    client = Search::Media::DefuddlerClient.new(
      http: http,
      resolver: ->(_host) { [ "8.8.8.8" ] }
    )

    assert_raises(Search::Media::DefuddlerClient::TransientError) do
      client.convert(url: "https://nationalpost.com/a")
    end
  end

  test "classifies HTTPX error responses as transient" do
    http = FakeHttp.new(ErrorResponse.new(IOError.new("connection reset")))
    client = Search::Media::DefuddlerClient.new(
      http: http,
      resolver: ->(_host) { [ "8.8.8.8" ] }
    )

    error = assert_raises(Search::Media::DefuddlerClient::TransientError) do
      client.convert(url: "https://nationalpost.com/a")
    end
    assert_equal "connection reset", error.message
  end
end
