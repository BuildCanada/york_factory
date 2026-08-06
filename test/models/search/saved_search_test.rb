require "test_helper"

class Search::SavedSearchTest < ActiveSupport::TestCase
  test "normalizes and validates a realm-owned definition" do
    saved_search = SavedSearch.create!(
      user: users(:member),
      name: "National Post housing",
      realm: "media",
      definition: {
        realm: "media",
        mode: "lexical",
        text: "housing",
        filters: { all: [ { field: "publisher_domain", op: "eq", value: "nationalpost.com" } ] }
      },
      delivery_configuration: { channels: [ "email" ] }
    )

    assert_equal 1, saved_search.definition.fetch("version")
    assert_match(/\A[0-9a-f]{64}\z/, saved_search.definition_digest)
  end

  test "rejects raw or unknown filter fields" do
    saved_search = SavedSearch.new(
      user: users(:member),
      name: "Unsafe",
      realm: "media",
      definition: {
        version: 1,
        realm: "media",
        mode: "filter_only",
        filters: { all: [ { field: "ner_payload", op: "eq", value: "secret" } ] }
      },
      delivery_configuration: { channels: [ "email" ] }
    )

    refute saved_search.valid?
    assert saved_search.errors[:definition].any? { |message| message.include?("ner_payload") }
  end

  test "rejects a definition claiming a different realm" do
    saved_search = SavedSearch.new(
      user: users(:member),
      name: "Confused",
      realm: "media",
      definition: { version: 1, realm: "kpi", mode: "filter_only" },
      delivery_configuration: { channels: [ "email" ] }
    )

    refute saved_search.valid?
    assert_includes saved_search.errors[:definition], "realm must match the saved search"
  end

  test "notification batch closes to an immutable delivery set" do
    saved_search = SavedSearch.create!(
      user: users(:member),
      name: "News",
      realm: "media",
      definition: { version: 1, realm: "media", mode: "filter_only" },
      delivery_configuration: {
        channels: [ "email", "webhook" ],
        webhook_url: "https://example.com/hooks/search"
      }
    )
    feed = Warehouse::MediaFeed.create!(name: "Batch feed #{SecureRandom.hex(3)}",
      strategy: "rss", url: "https://nationalpost.com/feed/", cadence_seconds: 300,
      publisher_name: "National Post", publisher_domain: "nationalpost.com", language: "en")
    article = Warehouse::MediaArticle.new(feed:,
      external_key: SecureRandom.uuid, title: "News", content: "News body", language: "en",
      realm_data: { "content_type" => "article", "publisher_name" => "National Post",
        "publisher_domain" => "nationalpost.com", "authors" => [], "word_count" => 2 })
    article.publish!
    match = saved_search.matches.create!(searchable: article)
    batch = saved_search.notification_batches.create!(mode: "instant")
    match.update!(notification_batch: batch)

    batch.close!

    assert_equal "closed", batch.state
    assert_equal %w[email webhook], batch.notification_deliveries.order(:channel).pluck(:channel)
    assert_not match.update(notification_batch: nil)
  end

  test "KPI matches snapshot the measure without observation values" do
    saved_search = SavedSearch.create!(user: users(:member), name: "Updated KPI", realm: "kpi",
      definition: { version: 1, realm: "kpi", mode: "filter_only",
        filters: { field: "kpi_last_updated_at", op: "gte", value: "2026-01-01T00:00:00Z" } },
      delivery_configuration: { channels: [ "email" ] })
    measure = kpi_measure
    match = saved_search.matches.create!(searchable: measure)

    assert_equal measure.search_id, match.match_key
    assert_equal measure.search_revision, match.searchable_revision
    refute measure.search_data.fetch(:realm_data).key?("kpi_value_numeric")
  end

  private

  def kpi_measure
    suffix = SecureRandom.hex(4)
    jurisdiction = Warehouse::Jurisdiction.create!(code: "SS-#{suffix}", name: "Saved search #{suffix}",
      slug: "saved-search-#{suffix}", level: "municipal", fiscal_year_start_month: 1,
      default_currency: "CAD")
    unit = Warehouse::Unit.create!(symbol: "count-#{suffix}", kind: "absolute", base_unit: "count", scale: 1)
    organization = Warehouse::Organization.create!(jurisdiction: jurisdiction,
      slug: "saved-search-org-#{suffix}", canonical_name: "Saved Search Organization #{suffix}")
    measure = Warehouse::Measure.create!(organization: organization, unit: unit,
      slug: "permit-time-#{suffix}", canonical_name: "Permit processing time", frequency: "annual")
    measure.update_columns(search_revision: 1, search_content_hash: "kpi-content-hash",
      search_index_sequence: 77)
    measure
  end
end
