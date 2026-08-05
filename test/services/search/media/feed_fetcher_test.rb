require "test_helper"

class Search::Media::FeedFetcherTest < ActiveSupport::TestCase
  FakeResponse = Data.define(:status, :headers, :body)
  ErrorResponse = Data.define(:error)

  FakeHttp = Struct.new(:response, :request) do
    def get(url, **options)
      self.request = { url:, **options }
      response
    end
  end

  SequenceHttp = Struct.new(:responses, :requests) do
    def get(url, **options)
      self.requests ||= []
      requests << { url:, **options }
      responses.shift
    end
  end

  test "parses RSS entries and sends conditional headers" do
    response = FakeResponse.new(
      status: 200,
      headers: { "etag" => '"v2"', "last-modified" => "Tue, 05 Aug 2026 12:00:00 GMT" },
      body: rss_body
    )
    http = FakeHttp.new(response)

    result = fetcher(http).call(
      url: "https://nationalpost.com/feed/",
      etag: '"v1"',
      last_modified: "Mon, 04 Aug 2026 12:00:00 GMT"
    )

    assert_equal 1, result.entries.size
    assert_equal "https://nationalpost.com/news/story", result.entries.first.fetch("url")
    assert_equal "A story", result.entries.first.fetch("title")
    assert_equal '"v2"', result.etag
    assert_equal '"v1"', http.request.dig(:headers, "If-None-Match")
  end

  test "returns no entries for a not modified feed" do
    response = FakeResponse.new(
      status: 304,
      headers: {},
      body: ""
    )

    result = fetcher(FakeHttp.new(response)).call(
      url: "https://nationalpost.com/feed/"
    )

    assert_empty result.entries
  end

  test "recovers entries from malformed publisher XML" do
    response = FakeResponse.new(
      status: 200,
      headers: {},
      body: <<~XML,
        <rss><channel><item><title>Recovered story</title>
        <link>https://www.thestar.com/news/story?utm_source=rss</link>
        <description><defer src="broken></description>
        <pubDate>Tue, 05 Aug 2026 11:00:00 GMT</pubDate></item></channel></rss>
      XML
    )

    result = fetcher(FakeHttp.new(response)).call(
      url: "https://www.thestar.com/feed"
    )

    assert_equal 1, result.entries.size
    assert_equal "Recovered story", result.entries.first.fetch("title")
    assert_equal "https://www.thestar.com/news/story", result.entries.first.fetch("url")
  end

  test "classifies HTTP failures for retry policy" do
    not_found = FakeResponse.new(status: 404, headers: {}, body: "not found")
    throttled = FakeResponse.new(status: 429, headers: {}, body: "slow down")

    assert_raises(Search::Media::FeedFetcher::PermanentError) do
      fetcher(FakeHttp.new(not_found)).call(url: "https://example.com/feed")
    end
    assert_raises(Search::Media::FeedFetcher::TransientError) do
      fetcher(FakeHttp.new(throttled)).call(url: "https://example.com/feed")
    end
  end

  test "classifies HTTPX error responses as transient" do
    error = assert_raises(Search::Media::FeedFetcher::TransientError) do
      fetcher(FakeHttp.new(ErrorResponse.new(IOError.new("TLS connection failed")))).call(
        url: "https://example.com/feed"
      )
    end

    assert_equal "TLS connection failed", error.message
  end

  test "revalidates a redirect target before following it" do
    http = SequenceHttp.new([
      FakeResponse.new(status: 302, headers: { "location" => "https://nationalpost.com/feed/" }, body: ""),
      FakeResponse.new(status: 200, headers: {}, body: rss_body)
    ])
    resolved_hosts = []
    fetcher = Search::Media::FeedFetcher.new(
      http: http,
      resolver: ->(host) { resolved_hosts << host; [ "8.8.8.8" ] }
    )

    result = fetcher.call(url: "https://example.com/feed")

    assert_equal [ "example.com", "nationalpost.com" ], resolved_hosts
    assert_equal "https://nationalpost.com/feed/", result.url
    assert_equal 2, http.requests.size
  end

  test "rejects oversized feed responses" do
    response = FakeResponse.new(
      status: 200,
      headers: {},
      body: "x" * (Search::Media::FeedFetcher::MAX_RESPONSE_BYTES + 1)
    )

    assert_raises(Search::Media::FeedFetcher::PermanentError) do
      fetcher(FakeHttp.new(response)).call(url: "https://example.com/feed")
    end
  end

  private

  def fetcher(http)
    Search::Media::FeedFetcher.new(
      http: http,
      resolver: ->(_host) { [ "8.8.8.8" ] }
    )
  end

  def rss_body
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>National Post</title>
          <link>https://nationalpost.com/</link>
          <description>News</description>
          <item>
            <guid>story-1</guid>
            <title>A story</title>
            <link>https://nationalpost.com/news/story?utm_source=rss</link>
            <description><![CDATA[Story summary]]></description>
            <pubDate>Tue, 05 Aug 2026 11:00:00 GMT</pubDate>
          </item>
        </channel>
      </rss>
    XML
  end
end
