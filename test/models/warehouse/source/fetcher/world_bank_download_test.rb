require "test_helper"

class Warehouse::Source::Fetcher::WorldBankDownloadTest < ActiveSupport::TestCase
  FakeResponse = Struct.new(:status, :body)

  class FakeHttp
    attr_reader :requested_urls

    def initialize(responses_by_page)
      @responses_by_page = responses_by_page
      @requested_urls = []
    end

    def get(url)
      @requested_urls << url
      page = url[/page=(\d+)/, 1].to_i
      @responses_by_page.fetch(page)
    end
  end

  test "concatenates all pages into one canonical sorted JSON body" do
    row = ->(country, year, value) {
      { "indicator" => { "id" => "TEST" }, "countryiso3code" => country, "date" => year, "value" => value }
    }
    http = FakeHttp.new(
      1 => FakeResponse.new(200, JSON.generate([ { "page" => 1, "pages" => 2 }, [ row.("USA", "2020", 2.0), row.("CAN", "2021", 3.0) ] ])),
      2 => FakeResponse.new(200, JSON.generate([ { "page" => 2, "pages" => 2 }, [ row.("CAN", "2020", 1.0) ] ]))
    )

    body = Warehouse::Source::Fetcher::WorldBankDownload.new("https://api.worldbank.org/v2/x?format=json", http: http).call
    rows = JSON.parse(body)

    assert_equal 2, http.requested_urls.size
    assert http.requested_urls.first.include?("&page=1")
    assert_equal [ %w[CAN 2020], %w[CAN 2021], %w[USA 2020] ],
                 rows.map { |r| [ r["countryiso3code"], r["date"] ] }
  end

  test "raises on a World Bank error envelope" do
    http = FakeHttp.new(
      1 => FakeResponse.new(200, JSON.generate([ { "message" => [ { "id" => "120", "value" => "Invalid indicator" } ] } ]))
    )

    error = assert_raises(RuntimeError) do
      Warehouse::Source::Fetcher::WorldBankDownload.new("https://api.worldbank.org/v2/x", http: http).call
    end
    assert_match(/Unexpected World Bank response/, error.message)
  end

  test "raises on non-200 responses" do
    http = FakeHttp.new(1 => FakeResponse.new(503, ""))

    assert_raises(RuntimeError) do
      Warehouse::Source::Fetcher::WorldBankDownload.new("https://api.worldbank.org/v2/x", http: http).call
    end
  end

  test "tolerates a UTF-8 BOM in the response body" do
    row = { "indicator" => { "id" => "TEST" }, "countryiso3code" => "CAN", "date" => "2020", "value" => 1.0 }
    body = "\uFEFF" + JSON.generate([ { "page" => 1, "pages" => 1 }, [ row ] ])
    http = FakeHttp.new(1 => FakeResponse.new(200, body))

    rows = JSON.parse(Warehouse::Source::Fetcher::WorldBankDownload.new("https://api.worldbank.org/v2/x", http: http).call)
    assert_equal [ "CAN" ], rows.map { |r| r["countryiso3code"] }
  end
end
