require "test_helper"

class Warehouse::Source::Fetcher::StreamingDownloadTest < ActiveSupport::TestCase
  FakeResponse = Data.define(:status, :chunks) do
    def each(&block)
      chunks.each(&block)
    end
  end

  class FakeHttp
    attr_reader :requests

    def initialize(chunks)
      @chunks = chunks
      @requests = []
    end

    def get(url, **options)
      @requests << { url: url, **options }
      FakeResponse.new(200, @chunks)
    end
  end

  test "streams chunks to disk, normalizes mixed line endings, and calculates the canonical checksum" do
    http = FakeHttp.new([ "first,second\r", "\nthird,fourth\n" ])
    result = Warehouse::Source::Fetcher::StreamingDownload.new("https://example.test/data.csv", http: http).call

    assert_equal "first,second\nthird,fourth\n", result.io.read
    assert_equal Digest::SHA256.hexdigest("first,second\nthird,fourth\n"), result.checksum
    assert_equal [ { url: "https://example.test/data.csv", stream: true } ], http.requests
  ensure
    result&.io&.close!
  end

  test "rejects a non-success response instead of archiving its error body" do
    http = FakeHttp.new([ "temporarily unavailable" ])
    http.define_singleton_method(:get) { |_url, **_options| FakeResponse.new(503, [ "temporarily unavailable" ]) }

    error = assert_raises(RuntimeError) do
      Warehouse::Source::Fetcher::StreamingDownload.new("https://example.test/data.csv", http: http).call
    end

    assert_match(/HTTP 503/, error.message)
  end

  test "rejects an empty response" do
    error = assert_raises(RuntimeError) do
      Warehouse::Source::Fetcher::StreamingDownload.new(
        "https://example.test/data.csv", http: FakeHttp.new([])
      ).call
    end

    assert_match(/Empty response/, error.message)
  end
end
