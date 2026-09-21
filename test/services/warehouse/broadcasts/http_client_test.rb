require "test_helper"

class Warehouse::Broadcasts::HttpClientTest < ActiveSupport::TestCase
  Response = Data.define(:status, :headers, :body)

  test "follows bounded redirects and enforces the host policy at every hop" do
    http = FakeHttp.new(
      "https://www.cpac.ca/start" => response(302, "", "location" => "https://evil.example/live"),
      "https://evil.example/live" => response(200, "media")
    )
    client = build_client(http)

    error = assert_raises(Warehouse::Broadcasts::HttpClient::PermanentError) do
      client.get("https://www.cpac.ca/start", allowed_hosts: %w[www.cpac.ca])
    end
    assert_match(/not allowed/, error.message)
    assert_equal [ "https://www.cpac.ca/start" ], http.requests
  end

  test "requires an exact 206 Content-Range and body length" do
    url = "https://media.example.test/segment.ts"
    valid = build_client(FakeHttp.new(url => response(206, "abcd", "content-range" => "bytes 10-13/100")))
    result = valid.get(url, headers: { "Range" => "bytes=10-13" })
    assert_equal "abcd", result.body

    ignored = build_client(FakeHttp.new(url => response(200, "whole file")))
    assert_raises(Warehouse::Broadcasts::HttpClient::PermanentError) do
      ignored.get(url, headers: { "Range" => "bytes=10-13" })
    end

    truncated = build_client(FakeHttp.new(url => response(206, "abc", "content-range" => "bytes 10-13/100")))
    assert_raises(Warehouse::Broadcasts::HttpClient::PermanentError) do
      truncated.get(url, headers: { "Range" => "bytes=10-13" })
    end
  end

  test "rejects response bodies above the configured limit" do
    url = "https://media.example.test/large"
    client = build_client(FakeHttp.new(url => response(200, "12345")))

    assert_raises(Warehouse::Broadcasts::HttpClient::PermanentError) do
      client.get(url, max_bytes: 4)
    end
  end

  private

  def response(status, body, headers = {})
    Response.new(status:, body:, headers: headers.with_indifferent_access)
  end

  def build_client(http)
    Warehouse::Broadcasts::HttpClient.new(http:, resolver: ->(_host) { [ "93.184.216.34" ] })
  end

  class FakeHttp
    attr_reader :requests

    def initialize(responses)
      @responses = responses
      @requests = []
    end

    def get(url, **)
      @requests << url
      @responses.fetch(url)
    end
  end
end
