require "test_helper"

class Warehouse::Source::Fetcher::StatcanVectorsTest < ActiveSupport::TestCase
  FakeResponse = Struct.new(:status, :body)

  class FakeHttp
    attr_reader :requested

    def initialize(response)
      @response = response
      @requested = []
    end

    def post(url, headers:, body:)
      @requested << { url: url, headers: headers, body: body }
      @response
    end
  end

  SOURCE_URL = "https://www150.statcan.gc.ca/t1/wds/rest/getDataFromVectorsAndLatestNPeriods?vectors=96730402,96730403&latestN=80".freeze

  test "posts the vectors payload and normalizes to one canonical sorted JSON body" do
    wds_response = JSON.generate([
      {
        "status" => "SUCCESS",
        "object" => {
          "vectorId" => 96730403,
          "vectorDataPoint" => [
            { "refPer" => "2021-01-01", "value" => 28.7 },
            { "refPer" => "2020-01-01", "value" => 29.1 }
          ]
        }
      },
      {
        "status" => "SUCCESS",
        "object" => {
          "vectorId" => 96730402,
          "vectorDataPoint" => [
            { "refPer" => "2020-01-01", "value" => 5.5 },
            { "refPer" => "2021-01-01", "value" => nil }
          ]
        }
      }
    ])
    http = FakeHttp.new(FakeResponse.new(200, wds_response))

    body = Warehouse::Source::Fetcher::StatcanVectors.new(SOURCE_URL, http: http).call
    rows = JSON.parse(body)

    request = http.requested.sole
    assert_equal "https://www150.statcan.gc.ca/t1/wds/rest/getDataFromVectorsAndLatestNPeriods", request[:url]
    assert_equal(
      [ { "vectorId" => 96730402, "latestN" => 80 }, { "vectorId" => 96730403, "latestN" => 80 } ],
      JSON.parse(request[:body])
    )

    assert_equal(
      [ [ 96730402, "2020-01-01", 5.5 ], [ 96730403, "2020-01-01", 29.1 ], [ 96730403, "2021-01-01", 28.7 ] ],
      rows.map { |r| [ r["vectorId"], r["refPer"], r["value"] ] }
    )
  end

  test "raises when a vector item is not SUCCESS" do
    http = FakeHttp.new(FakeResponse.new(200, JSON.generate([
      { "status" => "FAILED", "object" => { "responseStatusCode" => 2 } }
    ])))

    error = assert_raises(RuntimeError) do
      Warehouse::Source::Fetcher::StatcanVectors.new(SOURCE_URL, http: http).call
    end
    assert_match(/StatCan WDS returned FAILED/, error.message)
  end

  test "raises on non-200 responses" do
    http = FakeHttp.new(FakeResponse.new(503, ""))

    assert_raises(RuntimeError) do
      Warehouse::Source::Fetcher::StatcanVectors.new(SOURCE_URL, http: http).call
    end
  end

  test "raises when the url has no vectors param" do
    http = FakeHttp.new(FakeResponse.new(200, "[]"))

    assert_raises(RuntimeError) do
      Warehouse::Source::Fetcher::StatcanVectors.new("https://www150.statcan.gc.ca/t1/wds/rest/getDataFromVectorsAndLatestNPeriods", http: http).call
    end
  end
end
