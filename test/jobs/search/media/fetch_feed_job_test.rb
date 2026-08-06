require "test_helper"

class Search::Media::FetchFeedJobTest < ActiveJob::TestCase
  include ActiveJob::TestHelper

  Fetch = Struct.new(:metadata, :started, :succeeded, keyword_init: true) do
    def start!(at:)
      self.started = at
    end

    def succeed!(**attributes)
      self.succeeded = attributes
    end
  end

  Fetches = Struct.new(:fetch) do
    def create!
      fetch
    end
  end

  Feed = Struct.new(
    :id, :enabled?, :strategy, :url, :etag, :last_modified,
    :language, :fallback_url, :allow_http?, :fetches, keyword_init: true
  ) do
    def update!(**attributes)
      attributes.each { |name, value| public_send("#{name}=", value) }
    end
  end

  Fetcher = Struct.new(:result, :request, keyword_init: true) do
    def call(**attributes)
      self.request = attributes
      result
    end
  end

  FallbackFetcher = Struct.new(:result, :requests, keyword_init: true) do
    def call(**attributes)
      self.requests ||= []
      requests << attributes
      raise Search::Media::FeedFetcher::InvalidFeed, "HTML directory" if requests.one?

      result
    end
  end

  test "records feed success and enqueues each article independently" do
    fetch = Fetch.new(metadata: {})
    feed = Feed.new(
      id: 9,
      enabled?: true,
      strategy: "rss",
      url: "https://nationalpost.com/feed/",
      etag: '"v1"',
      language: "en",
      allow_http?: false,
      fetches: Fetches.new(fetch)
    )
    entries = [ { "url" => "https://nationalpost.com/one" }, { "url" => "https://nationalpost.com/two" } ]
    result = Search::Media::FeedFetcher::Result.new(
      entries: entries,
      etag: '"v2"',
      last_modified: nil,
      status: 200,
      url: feed.url,
      response_checksum: "checksum"
    )
    fetcher = Fetcher.new(result: result)

    job = Search::Media::FetchFeedJob.new
    job.define_singleton_method(:feed_for) { |_id| feed }
    job.define_singleton_method(:feed_fetcher) { fetcher }
    assert_enqueued_jobs 2, only: Search::Media::ImportArticleJob do
      job.perform(feed.id)
    end

    assert_equal(
      { url: feed.url, etag: '"v1"', last_modified: nil, allow_http: false },
      fetcher.request
    )
    assert fetch.started
    assert_equal "checksum", fetch.succeeded.fetch(:response_checksum)
    assert_equal 2, fetch.succeeded.fetch(:items_discovered)
    assert_equal '"v2"', feed.etag
  end

  test "uses an explicitly configured fallback when a legacy URL is no longer a feed" do
    fetch = Fetch.new(metadata: {})
    feed = Feed.new(
      id: 10,
      enabled?: true,
      strategy: "rss",
      url: "https://www.thestar.com/legacy-feed",
      language: "en",
      fallback_url: "https://www.thestar.com/search/?f=rss",
      allow_http?: false,
      fetches: Fetches.new(fetch)
    )
    result = Search::Media::FeedFetcher::Result.new(
      entries: [], etag: nil, last_modified: nil, status: 200,
      url: feed.fallback_url, response_checksum: "fallback-checksum"
    )
    fetcher = FallbackFetcher.new(result:)
    job = Search::Media::FetchFeedJob.new
    job.define_singleton_method(:feed_for) { |_id| feed }
    job.define_singleton_method(:feed_fetcher) { fetcher }

    job.perform(feed.id)

    assert_equal 2, fetcher.requests.size
    assert_equal feed.fallback_url, fetcher.requests.last.fetch(:url)
    assert_equal "fallback-checksum", fetch.succeeded.fetch(:response_checksum)
  end
end
