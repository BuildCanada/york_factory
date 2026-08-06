module Search
  module Media
    class FetchFeedJob < ApplicationJob
      retry_on FeedFetcher::TransientError, wait: :polynomially_longer, attempts: 5
      discard_on FeedFetcher::PermanentError

      def perform(feed_id)
        feed = feed_for(feed_id)
        return unless feed.enabled?

        started_at = Time.current
        fetch = feed.fetches.create!
        fetch.start!(at: started_at)
        result = fetch_feed(feed)

        if result.status == 304
          complete_not_modified!(fetch:, result:)
          return
        end

        result.entries.each do |entry|
          ImportArticleJob.perform_later(feed.id, entry)
        end
        finished_at = Time.current
        feed.update!(
          etag: result.etag,
          last_modified: result.last_modified
        )
        fetch.succeed!(
          http_status: result.status,
          items_discovered: result.entries.size,
          response_checksum: result.response_checksum,
          metadata: fetch.metadata.to_h.merge("resolved_feed_url" => result.url),
          at: finished_at
        )
      rescue => error
        mark_failed(feed, fetch, error)
        raise
      end

      private

      def feed_for(feed_id)
        Warehouse::MediaFeed.find(feed_id)
      end

      def feed_fetcher
        FeedFetcher.new
      end

      def fetch_feed(feed)
        feed_fetcher.call(
          url: feed.url,
          etag: feed.etag,
          last_modified: feed.last_modified,
          allow_http: feed.allow_http?
        )
      rescue FeedFetcher::InvalidFeed
        fallback_url = feed.fallback_url
        raise if fallback_url.blank?

        feed_fetcher.call(
          url: fallback_url,
          etag: feed.etag,
          last_modified: feed.last_modified,
          allow_http: false
        )
      end

      def complete_not_modified!(fetch:, result:)
        finished_at = Time.current
        fetch.succeed!(
          status: "not_modified",
          http_status: 304,
          response_checksum: result.response_checksum,
          metadata: fetch.metadata.to_h.merge("resolved_feed_url" => result.url),
          at: finished_at
        )
      end

      def mark_failed(feed, fetch, error)
        return unless feed&.persisted?

        finished_at = Time.current
        if fetch&.persisted?
          fetch.fail!(error: "#{error.class}: #{error.message}", at: finished_at)
        else
          feed.update_columns(
            last_failed_at: finished_at,
            consecutive_failures: feed.consecutive_failures.to_i + 1,
            next_fetch_at: finished_at + feed.cadence_seconds.seconds,
            updated_at: finished_at
          )
        end
      rescue => reporting_error
        Rails.logger.error("[Search::Media::FetchFeedJob] could not persist failure: #{reporting_error.message}")
      end
    end
  end
end
