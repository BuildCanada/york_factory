module Search
  module Media
    class FetchSourceJob < ApplicationJob
      queue_as :search_ingest

      retry_on FeedFetcher::TransientError, wait: :polynomially_longer, attempts: 5
      discard_on FeedFetcher::PermanentError

      def perform(source_id)
        source = source_for(source_id)
        return unless source.enabled? && source.realm == "media" && %w[rss atom].include?(source.strategy)

        started_at = Time.current
        fetch = source.fetches.create!
        fetch.start!(at: started_at)
        result = fetch_feed(source)

        if result.status == 304
          complete_not_modified!(source:, fetch:, result:, started_at:)
          return
        end

        result.entries.each do |entry|
          ImportArticleJob.perform_later(source.id, entry)
        end
        finished_at = Time.current
        source.update!(
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
        mark_failed(source, fetch, started_at, error)
        raise
      end

      private

      def source_for(source_id)
        Search::Source.find(source_id)
      end

      def feed_fetcher
        FeedFetcher.new
      end

      def fetch_feed(source)
        feed_fetcher.call(
          url: source.url,
          etag: source.etag,
          last_modified: source.last_modified,
          allow_http: source.configuration.to_h["allow_http"] == true
        )
      rescue FeedFetcher::InvalidFeed
        fallback_url = source.configuration.to_h["fallback_url"]
        raise if fallback_url.blank?

        feed_fetcher.call(
          url: fallback_url,
          etag: source.etag,
          last_modified: source.last_modified,
          allow_http: false
        )
      end

      def complete_not_modified!(source:, fetch:, result:, started_at:)
        finished_at = Time.current
        fetch.succeed!(
          status: "not_modified",
          http_status: 304,
          response_checksum: result.response_checksum,
          metadata: fetch.metadata.to_h.merge("resolved_feed_url" => result.url),
          at: finished_at
        )
      end

      def mark_failed(source, fetch, started_at, error)
        return unless source&.persisted?

        finished_at = Time.current
        if fetch&.persisted?
          fetch.fail!(error: "#{error.class}: #{error.message}", at: finished_at)
        else
          source.update_columns(
            last_failed_at: finished_at,
            consecutive_failures: source.consecutive_failures.to_i + 1,
            next_fetch_at: finished_at + source.cadence_seconds.seconds,
            updated_at: finished_at
          )
        end
      rescue => reporting_error
        Rails.logger.error("[Search::Media::FetchSourceJob] could not persist failure: #{reporting_error.message}")
      end
    end
  end
end
