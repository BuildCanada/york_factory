require "test_helper"

class SearchableRegistryTest < ActiveSupport::TestCase
  setup do
    Searchable.models.each do |model|
      model.update_all(search_index_sequence: nil, search_synced_at: nil)
    end
  end

  test "checkpoint and overlap cover every searchable model" do
    older = create_article
    newer = create_article
    older.update_columns(search_index_sequence: 40, search_synced_at: 5.minutes.ago)
    newer.update_columns(search_index_sequence: 44, search_synced_at: 1.minute.ago)

    assert_equal 44, Searchable.checkpoint
    assert_equal 39, Searchable.overlap_from_sequence(at: Time.current)
  end

  test "record and pending counts use each model's indexable scope" do
    baseline_records = Searchable.record_count
    baseline_pending = Searchable.pending_count
    draft = create_article(publish: false)

    assert_equal baseline_records, Searchable.record_count
    assert_equal baseline_pending, Searchable.pending_count

    draft.publish!

    assert_equal baseline_records + 1, Searchable.record_count
    assert_equal baseline_pending + 1, Searchable.pending_count

    draft.update_columns(search_index_sequence: 1, search_synced_at: Time.current)

    assert_equal baseline_pending, Searchable.pending_count
  end

  private

  def create_article(publish: true)
    article = Warehouse::MediaArticle.new(
      external_key: SecureRandom.uuid,
      title: "Index state article",
      content: "Index state body",
      language: "en",
      realm_data: {
        "content_type" => "article",
        "publisher_name" => "National Post",
        "publisher_domain" => "nationalpost.com",
        "authors" => [],
        "word_count" => 3
      }
    )
    publish ? article.publish! : article.save!
    article
  end
end
