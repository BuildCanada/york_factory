require "test_helper"

class Search::Media::ArticleNormalizerTest < ActiveSupport::TestCase
  Source = Data.define(:id, :configuration)

  test "normalizes Defuddler output into the media document contract" do
    source = Source.new(id: 42, configuration: { "language" => "en" })
    attributes = Search::Media::ArticleNormalizer.new.call(
      source: source,
      feed_entry: {
        url: "https://www.nationalpost.com/news/story?utm_source=rss",
        guid: "story-1",
        title: "Feed title",
        published_at: "2026-08-05T10:00:00Z"
      },
      extraction: {
        title: "<b>Extracted title</b>",
        content: "The full article body.",
        author: "Jane Reporter",
        description: "<p>A summary.</p>",
        wordCount: 4,
        language: "en",
        image: "https://nationalpost.com/image.jpg?utm_source=article"
      }
    )

    assert_not attributes.key?(:realm)
    assert_not attributes.key?(:record_type)
    assert_equal "https://www.nationalpost.com/news/story", attributes.fetch(:canonical_url)
    assert_equal "Extracted title", attributes.fetch(:title)
    assert_equal "National Post", attributes.dig(:realm_data, "publisher_name")
    assert_equal [ "Jane Reporter" ], attributes.dig(:realm_data, "authors")
    assert_equal 4, attributes.dig(:realm_data, "word_count")
    assert_equal "https://nationalpost.com/image.jpg", attributes.dig(:realm_data, "image_url")
  end

  test "rejects unsupported publishers" do
    source = Source.new(id: 42, configuration: {})

    assert_raises(Search::Media::ArticleNormalizer::Invalid) do
      Search::Media::ArticleNormalizer.new.call(
        source: source,
        feed_entry: { url: "https://example.com/story", title: "Story" },
        extraction: { content: "Body" }
      )
    end
  end
end
