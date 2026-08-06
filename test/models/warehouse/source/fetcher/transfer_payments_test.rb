require "test_helper"

class Warehouse::Source::Fetcher::TransferPaymentsTest < ActiveSupport::TestCase
  FakeResponse = Data.define(:status, :body) do
    def each
      body.bytes.each_slice(17) { |bytes| yield bytes.pack("C*") }
    end
  end

  class FakeHttp
    attr_reader :requests

    def initialize(responses)
      @responses = responses
      @requests = []
    end

    def get(url, **options)
      @requests << { url:, **options }
      @responses.fetch(url) { raise "unexpected request: #{url}" }
    end
  end

  SOURCE_URL = Warehouse::Source::Fetcher::TransferPayments::CATALOGUE_URL
  YEAR_2003_URL = "https://example.test/pt-tp-2003-eng.csv".freeze
  YEAR_2025_URL = "https://example.test/pt-tp-2025.csv".freeze

  test "discovers English historical and bilingual current CSVs and streams each independently" do
    body_2003 = csv("Fscl-yr_Ex-fin,Rcpt-class_Cat-bnfcrs_eng", "2002/2003,Program A")
    body_2025 = csv("Fscl-yr_Ex-fin,Rcpt-class_Cat-bnfcrs_eng", "2024/2025,Program B")
    http = fake_http(
      resources: [
        resource("2025 - Transfer Payments", YEAR_2025_URL),
        resource("2021 - Transfer Payments", "https://example.test/pt-tp-2021-fra.csv"),
        resource("2003 - Transfer Payments", YEAR_2003_URL),
        { "name" => "Data Dictionary", "format" => "XML", "url" => "https://example.test/dictionary.xml" }
      ],
      downloads: { YEAR_2003_URL => body_2003, YEAR_2025_URL => body_2025 }
    )

    downloads = fetched_downloads(http)
    canonical_2003 = body_2003.gsub("\r\n", "\n")
    canonical_2025 = body_2025.gsub("\r\n", "\n")

    assert_equal [ 2003, 2025 ], downloads.pluck(:year)
    assert_equal [ 2002, 2024 ], downloads.pluck(:fiscal_year)
    assert_equal [ canonical_2003, canonical_2025 ], downloads.pluck(:body)
    assert_equal [ Digest::SHA256.hexdigest(canonical_2003), Digest::SHA256.hexdigest(canonical_2025) ],
      downloads.pluck(:checksum)
    assert_equal [
      { url: SOURCE_URL },
      { url: YEAR_2003_URL, stream: true },
      { url: YEAR_2025_URL, stream: true }
    ], http.requests
  end

  test "can restrict downloads to selected catalogue years" do
    http = fake_http(
      resources: [
        resource("2003 - Transfer Payments", YEAR_2003_URL),
        resource("2025 - Transfer Payments", YEAR_2025_URL)
      ],
      downloads: { YEAR_2025_URL => "2024/2025" }
    )

    downloads = fetched_downloads(http, years: [ 2025 ])

    assert_equal [ 2025 ], downloads.pluck(:year)
    assert_equal [ { url: SOURCE_URL }, { url: YEAR_2025_URL, stream: true } ], http.requests
  end

  test "yields a completed year before a later download fails" do
    http = fake_http(
      resources: [
        resource("2003 - Transfer Payments", YEAR_2003_URL),
        resource("2025 - Transfer Payments", YEAR_2025_URL)
      ],
      downloads: {
        YEAR_2003_URL => "2002/2003",
        YEAR_2025_URL => FakeResponse.new(503, "unavailable")
      }
    )
    completed = []

    error = assert_raises(RuntimeError) do
      Warehouse::Source::Fetcher::TransferPayments.new(SOURCE_URL, http:).each_year do |download|
        completed << download.year
        download.io.close!
      end
    end

    assert_equal [ 2003 ], completed
    assert_match(/HTTP 503/, error.message)
  end

  test "rejects a catalogue without English yearly CSVs" do
    http = fake_http(
      resources: [ resource("2003 - Transfer Payments", "https://example.test/pt-tp-2003-fra.csv") ]
    )

    error = assert_raises(RuntimeError) do
      Warehouse::Source::Fetcher::TransferPayments.new(SOURCE_URL, http:).each_year.to_a
    end

    assert_match(/no English yearly CSVs/, error.message)
  end

  private

  def fetched_downloads(http, years: nil)
    [].tap do |downloads|
      Warehouse::Source::Fetcher::TransferPayments.new(SOURCE_URL, http:, years:).each_year do |download|
        downloads << download.to_h.merge(body: download.io.read)
        download.io.close!
      end
    end
  end

  def fake_http(resources:, downloads: {})
    catalogue = JSON.generate("success" => true, "result" => { "resources" => resources })
    responses = downloads.transform_values { |value| value.is_a?(FakeResponse) ? value : FakeResponse.new(200, value) }
    FakeHttp.new({ SOURCE_URL => FakeResponse.new(200, catalogue) }.merge(responses))
  end

  def resource(name, url)
    { "name" => name, "name_translated" => { "en" => name }, "format" => "CSV", "url" => url }
  end

  def csv(header, *rows)
    ([ header ] + rows).join("\r\n")
  end
end
