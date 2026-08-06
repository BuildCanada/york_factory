require "test_helper"

class Warehouse::Source::Fetcher::CihrAwardsTest < ActiveSupport::TestCase
  FakeResponse = Data.define(:status, :body)

  class FakeHttp
    attr_reader :requests

    def initialize(responses)
      @responses = responses
      @requests = []
    end

    def post(url, **options)
      @requests << { url: url, **options }
      @responses.shift || raise("unexpected request")
    end
  end

  SOURCE_URL = "https://webapps.cihr-irsc.gc.ca/decisions/p/main.html?lang=en".freeze

  test "pages through plain Solr JSON and returns canonical response docs" do
    http = FakeHttp.new([
      response(num_found: 3, docs: [ document("1"), document("2") ]),
      response(num_found: 3, docs: [ document("3") ])
    ])

    download = Warehouse::Source::Fetcher::CihrAwards.new(
      SOURCE_URL, http: http, rows_per_page: 2, max_pages: 2
    ).call
    documents = download.io.each_line.map { |line| JSON.parse(line) }

    assert_equal %w[1 2 3], documents.pluck("id")
    assert_equal Digest::SHA256.file(download.io.path).hexdigest, download.checksum
    assert_equal 2, http.requests.size
    assert_equal [ 0, 2 ], http.requests.map { |request| form(request).fetch("start").to_i }
    assert_equal "json", form(http.requests.first).fetch("wt")
    refute form(http.requests.first).key?("json.wrf")
    refute http.requests.first.dig(:headers).key?("Cookie")
    assert_equal "https://webapps.cihr-irsc.gc.ca/decisions/sq", http.requests.first.fetch(:url)
  ensure
    download&.io&.close!
  end

  test "rejects a malformed Solr envelope" do
    http = FakeHttp.new([ FakeResponse.new(200, JSON.generate("response" => { "docs" => [] })) ])

    error = assert_raises(RuntimeError) do
      Warehouse::Source::Fetcher::CihrAwards.new(SOURCE_URL, http: http).call
    end

    assert_match(/Unexpected CIHR response/, error.message)
  end

  test "raises on non-200 responses" do
    http = FakeHttp.new([ FakeResponse.new(503, "unavailable") ])

    error = assert_raises(RuntimeError) do
      Warehouse::Source::Fetcher::CihrAwards.new(SOURCE_URL, http: http).call
    end

    assert_match(/HTTP 503/, error.message)
  end

  test "bounds pagination" do
    http = FakeHttp.new([ response(num_found: 2, docs: [ document("1") ]) ])

    error = assert_raises(RuntimeError) do
      Warehouse::Source::Fetcher::CihrAwards.new(
        SOURCE_URL, http: http, rows_per_page: 1, max_pages: 1
      ).call
    end

    assert_match(/exceeded 1 pages/, error.message)
  end

  test "rejects duplicate award ids across pages" do
    http = FakeHttp.new([
      response(num_found: 2, docs: [ document("1") ]),
      response(num_found: 2, docs: [ document("1") ])
    ])

    error = assert_raises(RuntimeError) do
      Warehouse::Source::Fetcher::CihrAwards.new(
        SOURCE_URL, http: http, rows_per_page: 1, max_pages: 2
      ).call
    end

    assert_match(/duplicate award ids/, error.message)
  end

  test "rejects out-of-order ids instead of buffering the result set to sort it" do
    http = FakeHttp.new([
      response(num_found: 2, docs: [ document("2") ]),
      response(num_found: 2, docs: [ document("1") ])
    ])

    error = assert_raises(RuntimeError) do
      Warehouse::Source::Fetcher::CihrAwards.new(
        SOURCE_URL, http: http, rows_per_page: 1, max_pages: 2
      ).call
    end

    assert_match(/out-of-order award id: 1/, error.message)
  end

  private

  def document(id)
    { "id" => id, "projecttitle" => [ "Project #{id}" ], "cihramount2" => [ "$1,000" ] }
  end

  def response(num_found:, docs:)
    FakeResponse.new(200, JSON.generate("response" => { "numFound" => num_found, "docs" => docs }))
  end

  def form(request)
    Rack::Utils.parse_query(request.fetch(:body))
  end
end
