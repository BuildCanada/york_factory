require "test_helper"

class Search::CoreTest < ActiveSupport::TestCase
  setup do
    @source = Search::Source.create!(
      name: "Test National Post #{SecureRandom.hex(4)}",
      realm: "media",
      strategy: "rss",
      url: "https://nationalpost.com/feed/",
      cadence_seconds: 300,
      configuration: {}
    )
  end

  test "publishing a valid document writes one revision" do
    document = build_media_document

    assert_same document, document.publish!

    assert_equal "published", document.state
    assert_equal 1, document.search_revision
    assert_nil document.reload.search_index_sequence
    assert_equal "media", document.realm
    assert_equal "An article body", document.search_data.fetch(:content)
  end

  test "rediscovering unchanged material only updates last seen" do
    document = build_media_document
    document.title = "  A title  "
    document.publish!(seen_at: 1.hour.ago)
    sequence = document.search_index_sequence

    document.publish!(seen_at: Time.current)

    assert_equal 1, document.reload.search_revision
    assert_nil sequence
    assert_nil document.search_index_sequence
    assert_in_delta Time.current, document.last_seen_at, 2.seconds
  end

  test "material update and withdrawal each create a new revision" do
    document = build_media_document
    document.publish!

    document.content = "A materially updated article body"
    document.publish!
    assert_equal 2, document.search_revision

    document.withdraw!
    assert_equal 3, document.search_revision
    assert_equal "withdrawn", document.state
  end

  test "a withdrawn article can be republished" do
    document = build_media_document
    document.publish!
    document.withdraw!

    document.publish!

    assert_equal "published", document.reload.state
    assert_equal 3, document.search_revision
  end

  test "realm contract rejects unknown fields and publishers" do
    document = build_media_document
    document.realm_data["publisher_domain"] = "example.com"
    document.realm_data["secret_internal_field"] = "nope"

    error = assert_raises(ActiveRecord::RecordInvalid) { document.publish! }

    assert_includes error.record.errors[:realm_data], "publisher_domain is not supported"
    assert error.record.errors[:realm_data].any? { |message| message.include?("secret_internal_field") }
    refute document.persisted?
  end

  private

  def build_media_document
    Search::MediaArticle.new(
      source: @source,
      external_key: SecureRandom.uuid,
      canonical_url: "https://nationalpost.com/news/#{SecureRandom.hex(4)}",
      source_url: "https://nationalpost.com/feed/",
      title: "A title",
      content: "An article body",
      language: "en",
      realm_data: {
        "content_type" => "article",
        "publisher_name" => "National Post",
        "publisher_domain" => "nationalpost.com",
        "authors" => [ "Reporter" ],
        "word_count" => 3
      }
    )
  end
end
