require "test_helper"

class Metrics::SubstackClientTest < ActiveSupport::TestCase
  Response = Data.define(:status, :body)

  class FakeHTTP
    attr_reader :requests

    def initialize(response)
      @response = response
      @requests = []
    end

    def get(url, params:, headers:)
      @requests << { url: url, params: params, headers: headers }
      @response
    end
  end

  test "sends auth cookies and parses JSON" do
    http = FakeHTTP.new(Response.new(200, '{"id":4062955}'))
    client = Metrics::SubstackClient.new(
      base_url: "https://buildcanada.substack.com",
      cookies: { "substack.sid" => "secret", "csrf" => "token" },
      http: http
    )

    assert_equal({ "id" => 4_062_955 }, client.get("/api/v1/publication"))
    request = http.requests.sole
    assert_equal "https://buildcanada.substack.com/api/v1/publication", request[:url]
    assert_equal "substack.sid=secret; csrf=token", request[:headers]["Cookie"]
  end

  test "raises a typed rate-limit error" do
    http = FakeHTTP.new(Response.new(429, '{"error":"slow down"}'))
    client = Metrics::SubstackClient.new(
      base_url: "https://buildcanada.substack.com",
      http: http
    )

    error = assert_raises(Metrics::SubstackClient::RateLimitError) do
      client.get("/api/v1/archive")
    end
    assert_match "slow down", error.message
  end

  test "requires an HTTPS publication URL" do
    assert_raises(ArgumentError) do
      Metrics::SubstackClient.new(base_url: "http://buildcanada.substack.com")
    end
  end
end
