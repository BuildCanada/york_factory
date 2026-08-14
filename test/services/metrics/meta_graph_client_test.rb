require "test_helper"

class Metrics::MetaGraphClientTest < ActiveSupport::TestCase
  Response = Data.define(:status, :body)

  class FakeHttp
    attr_reader :requests

    def initialize(response)
      @response = response
      @requests = []
    end

    def get(url, params:)
      @requests << [ url, params ]
      @response
    end
  end

  test "finds a Page access token without exposing unrelated Page tokens" do
    http = FakeHttp.new(Response.new(200, {
      data: [
        { id: "page-1", access_token: "page-token-1" },
        { id: "page-2", access_token: "page-token-2" }
      ]
    }.to_json))
    client = Metrics::MetaGraphClient.new(access_token: "system-token", http: http)

    assert_equal "page-token-2", client.page_access_token("page-2")
    assert_equal({ fields: "id,access_token", limit: 100 }, http.requests.sole.second)
  end

  test "raises when the Page is not assigned to the system user" do
    http = FakeHttp.new(Response.new(200, { data: [] }.to_json))
    client = Metrics::MetaGraphClient.new(access_token: "system-token", http: http)

    error = assert_raises(Metrics::MetaGraphClient::Error) do
      client.page_access_token("missing")
    end
    assert_match "did not return an access token", error.message
  end
end
