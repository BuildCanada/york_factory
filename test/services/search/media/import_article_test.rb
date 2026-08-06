require "test_helper"

class Warehouse::MediaArticleImportTest < ActiveSupport::TestCase
  test "publishes a normalized article idempotently" do
    feed = Warehouse::MediaFeed.create!(
      name: "Import test National Post",
      strategy: "rss",
      url: "https://nationalpost.com/feed/",
      publisher_name: "National Post",
      publisher_domain: "nationalpost.com",
      language: "en",
      cadence_seconds: 300
    )
    feed_entry = {
      "url" => "https://nationalpost.com/news/import-test",
      "guid" => "import-test",
      "title" => "Feed title",
      "published_at" => "2026-08-05T10:00:00Z"
    }
    extraction = {
      "title" => "An imported article",
      "content" => "This is the extracted article body.",
      "author" => "Jane Reporter",
      "language" => "en"
    }
    assert_difference -> { Warehouse::MediaArticle.count }, 1 do
      result = Warehouse::MediaArticle.import!(feed:, feed_entry:, extraction:)
      assert result.changed
      assert_equal 1, result.article.search_revision
      assert_equal "published", result.article.state
      assert_equal "National Post", result.article.realm_data.fetch("publisher_name")
    end

    assert_no_difference -> { Warehouse::MediaArticle.count } do
      result = Warehouse::MediaArticle.import!(feed:, feed_entry:, extraction:)
      assert_not result.changed
      assert_equal 1, result.article.search_revision
    end
  end

  test "deduplicates an article discovered through overlapping feeds" do
    top_stories = Warehouse::MediaFeed.create!(
      name: "Toronto Star test top stories",
      strategy: "rss",
      url: "https://www.thestar.com/search/?f=rss&t=article&bl=2827101&l=20",
      publisher_name: "Toronto Star", publisher_domain: "thestar.com", language: "en",
      cadence_seconds: 300
    )
    politics = Warehouse::MediaFeed.create!(
      name: "Toronto Star test politics",
      strategy: "rss",
      url: "https://www.thestar.com/search/?f=rss&t=article&c=politics*",
      publisher_name: "Toronto Star", publisher_domain: "thestar.com", language: "en",
      cadence_seconds: 300
    )
    feed_entry = {
      "url" => "https://www.thestar.com/politics/a-shared-story.html?utm_source=rss",
      "guid" => "shared-story",
      "title" => "A shared story"
    }
    extraction = {
      "url" => "https://www.thestar.com/politics/a-shared-story.html",
      "title" => "A shared story",
      "content" => "The same article can appear in multiple Toronto Star feeds.",
      "language" => "en"
    }
    first = Warehouse::MediaArticle.import!(feed: top_stories, feed_entry:, extraction:)

    assert_no_difference -> { Warehouse::MediaArticle.count } do
      second = Warehouse::MediaArticle.import!(feed: politics, feed_entry:, extraction:)
      assert_equal first.article.id, second.article.id
      assert_equal top_stories.id, second.article.media_feed_id
      assert_not second.changed
    end
  end
end
