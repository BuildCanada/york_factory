require "test_helper"

class Search::Media::ImportArticleJobTest < ActiveJob::TestCase
  Source = Struct.new(:id, :enabled?, :realm, :configuration, keyword_init: true)
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
    source = Source.new(id: 7, enabled?: true, realm: "media", configuration: { "language" => "en" })
    feed_entry = { "url" => "https://nationalpost.com/story" }
    extraction = { "title" => "Story", "content" => "Body" }
    client = Client.new(extraction: extraction)
    article = Search::MediaArticle.new(title: "Story",
      content: "Body", language: "en", realm_data: { "content_type" => "article",
        "publisher_name" => "National Post", "publisher_domain" => "nationalpost.com",
        "authors" => [], "word_count" => 1 }).tap(&:publish!)
    article_class = ArticleClass.new(result: Search::MediaArticle::ImportResult.new(article: article, changed: true))

    job = Search::Media::ImportArticleJob.new
    job.define_singleton_method(:source_for) { |_id| source }
    job.define_singleton_method(:defuddler_client) { client }
    job.define_singleton_method(:media_article_class) { article_class }
    assert_enqueued_with(job: Search::SyncJob) do
      job.perform(source.id, feed_entry)
    end

    assert_equal({ url: feed_entry.fetch("url"), language: "en" }, client.request)
    assert_equal({ source:, feed_entry:, extraction: }, article_class.request)
  end
end
