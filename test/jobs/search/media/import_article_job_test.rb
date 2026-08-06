require "test_helper"

class Search::Media::ImportArticleJobTest < ActiveJob::TestCase
  Feed = Struct.new(:id, :enabled?, :language, keyword_init: true)
  Client = Struct.new(:extraction, :request, keyword_init: true) do
    def convert(**attributes)
      self.request = attributes
      extraction
    end
  end
  ArticleClass = Struct.new(:request, :result, keyword_init: true) do
    def import!(**attributes)
      self.request = attributes
      result
    end
  end

  test "extracts and imports one discovered article" do
    feed = Feed.new(id: 7, enabled?: true, language: "en")
    feed_entry = { "url" => "https://nationalpost.com/story" }
    extraction = { "title" => "Story", "content" => "Body" }
    client = Client.new(extraction: extraction)
    article = Warehouse::MediaArticle.new(title: "Story",
      content: "Body", language: "en", realm_data: { "content_type" => "article",
        "publisher_name" => "National Post", "publisher_domain" => "nationalpost.com",
        "authors" => [], "word_count" => 1 }).tap(&:publish!)
    article_class = ArticleClass.new(result: Warehouse::MediaArticle::ImportResult.new(article: article, changed: true))

    job = Search::Media::ImportArticleJob.new
    job.define_singleton_method(:feed_for) { |_id| feed }
    job.define_singleton_method(:defuddler_client) { client }
    job.define_singleton_method(:media_article_class) { article_class }
    assert_enqueued_with(job: Search::SyncJob) do
      job.perform(feed.id, feed_entry)
    end

    assert_equal({ url: feed_entry.fetch("url"), language: "en" }, client.request)
    assert_equal({ feed:, feed_entry:, extraction: }, article_class.request)
  end
end
