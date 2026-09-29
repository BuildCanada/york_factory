require "test_helper"

class Usage::ClientsTest < ActiveSupport::TestCase
  Response = Data.define(:status, :body)

  class RecordingHttp
    attr_reader :requests

    def initialize(answers) = (@answers = answers) && (@requests = [])

    def request(method, url, headers:, body: nil)
      @requests << { method:, url:, headers:, body: }
      status, json = @answers.fetch(URI.parse(url).path)
      Response.new(status:, body: JSON.generate(json))
    end
  end

  test "the Worker's usage endpoints are called signed, and a failure is nil" do
    key = issue_key.api_key
    http = RecordingHttp.new(
      "/internal/accounts/#{key.account_id}/usage" => [ 200, { "account_id" => key.account_id.to_s, "month" => { "period" => "2026-09", "units" => 30 },
                                                            "days" => [ { "period" => "2026-09-27", "units" => 12, "requests" => 10 }, { "period" => "bad" } ] } ],
      "/internal/keys/#{key.token_digest}/usage" => [ 503, {} ]
    )
    client = Edge::UsageClient.new(http:, url: "https://edge.test", secret: "edge-secret")
    assert_equal({ Date.new(2026, 9, 27) => 12 }, client.account_days(key.account, month: "2026-09"))
    request = http.requests.first
    assert_equal "https://edge.test/internal/accounts/#{key.account_id}/usage?month=2026-09", request[:url]
    assert Edge::Signature.valid?(method: "GET", path: "/internal/accounts/#{key.account_id}/usage?month=2026-09", body: "",
      timestamp: request[:headers]["BC-Edge-Timestamp"], signature: request[:headers]["BC-Edge-Signature"], secret: "edge-secret")
    assert_nil client.key(key)
    refute Edge::UsageClient.new(url: nil, secret: nil).configured?
  end

  test "the Analytics Engine client needs its credentials and a safe dataset name" do
    refute AnalyticsEngineClient.new(account_id: "", api_token: "t").configured?
    assert_raises(AnalyticsEngineClient::NotConfigured) { AnalyticsEngineClient.new(account_id: nil, api_token: nil).query("SELECT 1") }
    assert_raises(ArgumentError) { AnalyticsEngineClient.new(account_id: "a", api_token: "t", dataset: "x; DROP") }
    assert_equal "toDateTime('2026-09-29 12:00:00')", AnalyticsEngineClient.time(Time.utc(2026, 9, 29, 12))
  end
end
