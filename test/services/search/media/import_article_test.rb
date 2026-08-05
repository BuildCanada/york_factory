require "test_helper"

class Search::MediaArticleImportTest < ActiveSupport::TestCase
  test "publishes a normalized article idempotently" do
    source = Search::Source.create!(
      name: "Import test National Post",
      realm: "media",
      strategy: "rss",
      url: "https://nationalpost.com/feed/",
      configuration: { "language" => "en" },
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
    assert_difference -> { Search::MediaArticle.count }, 1 do
      result = Search::MediaArticle.import!(source:, feed_entry:, extraction:)
      assert result.changed
      assert_equal 1, result.article.search_revision
      assert_equal "published", result.article.state
      assert_equal "National Post", result.article.realm_data.fetch("publisher_name")
    end

    assert_no_difference -> { Search::MediaArticle.count } do
      result = Search::MediaArticle.import!(source:, feed_entry:, extraction:)
      assert_not result.changed
      assert_equal 1, result.article.search_revision
    end
  end

  test "deduplicates an article discovered through overlapping feeds" do
    top_stories = Search::Source.create!(
      name: "Toronto Star test top stories",
      realm: "media",
      strategy: "rss",
      url: "https://www.thestar.com/search/?f=rss&t=article&bl=2827101&l=20",
      configuration: { "language" => "en" },
      cadence_seconds: 300
    )
    politics = Search::Source.create!(
      name: "Toronto Star test politics",
      realm: "media",
      strategy: "rss",
      url: "https://www.thestar.com/search/?f=rss&t=article&c=politics*",
      configuration: { "language" => "en" },
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
    first = Search::MediaArticle.import!(source: top_stories, feed_entry:, extraction:)

    assert_no_difference -> { Search::MediaArticle.count } do
      second = Search::MediaArticle.import!(source: politics, feed_entry:, extraction:)
      assert_equal first.article.id, second.article.id
      assert_equal top_stories.id, second.article.search_source_id
      assert_not second.changed
    end
  end
end
