module Search
  module Media
    class ImportArticleJob < ApplicationJob
      retry_on TransientError, wait: :polynomially_longer, attempts: 6
      discard_on ArticleNormalizer::Invalid, SafeUrl::Invalid

      def perform(feed_id, feed_entry)
        feed = feed_for(feed_id)
        return unless feed.enabled?

        extraction = defuddler_client.convert(
          url: feed_entry.fetch("url"),
          language: feed.language
        )
        result = media_article_class.import!(feed:, feed_entry:, extraction:)
        Search::SyncJob.perform_later(result.article) if result.changed
        result
      end

      private

      def feed_for(feed_id)
        Warehouse::MediaFeed.find(feed_id)
      end

      def defuddler_client
        DefuddlerClient.new
      end

      def media_article_class
        Warehouse::MediaArticle
      end
    end
  end
end
