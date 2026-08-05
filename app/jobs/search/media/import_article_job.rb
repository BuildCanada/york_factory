module Search
  module Media
    class ImportArticleJob < ApplicationJob
      queue_as :search_ingest

      retry_on DefuddlerClient::TransientError, wait: :polynomially_longer, attempts: 6
      discard_on ArticleNormalizer::Invalid, SafeUrl::Invalid

      def perform(source_id, feed_entry)
        source = source_for(source_id)
        return unless source.enabled? && source.realm == "media"

        extraction = defuddler_client.convert(
          url: feed_entry.fetch("url"),
          language: source.configuration.to_h["language"]
        )
        result = media_article_class.import!(source:, feed_entry:, extraction:)
        Search::SyncJob.perform_later(result.article) if result.changed
        result
      end

      private

      def source_for(source_id)
        Search::Source.find(source_id)
      end

      def defuddler_client
        DefuddlerClient.new
      end

      def media_article_class
        Search::MediaArticle
      end
    end
  end
end
