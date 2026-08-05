require "test_helper"

class SearchableTest < ActiveSupport::TestCase
  class EmbeddingClient
    def embed_documents(_texts)
      Search::Embedding::AzureCohereClient::Result.new(
        vectors: [ Array.new(1_024, 0.1) ],
        model: "embed-v-4-0",
        input_type: "document",
        usage: { "input_tokens" => 12 },
        request_id: "embedding-test"
      )
    end
  end

  class Namespace
    attr_reader :writes

    def initialize(error: nil)
      @error = error
      @writes = []
    end

    def write(**options)
      raise @error if @error

      @writes << options
      rows = Array(options[:upsert_rows])
      { upserted_ids: rows.map { |row| row.fetch(:id) }, rows_affected: rows.length }
    end
  end

  test "a media article owns its Turbopuffer row and sync metadata" do
    article = media_article
    namespace = Namespace.new

    result = article.sync_to_search!(namespace:, embedding_client: EmbeddingClient.new)

    row = namespace.writes.sole.fetch(:upsert_rows).sole
    assert_equal article.search_id, row.fetch(:id)
    assert_equal "media", row.fetch(:realm)
    assert_equal "article", row.fetch(:record_type)
    assert_equal 1_024, row.fetch(:embedding).length
    assert_equal article.reload.search_index_sequence, row.fetch(:index_sequence)
    assert article.search_synced_at.present?
    assert_equal "embed-v-4-0", article.search_embedding_model
    assert_equal [ article.search_id ], result.fetch(:upserted_ids)
    assert_equal article, Searchable.resolve(article.search_id)
  end

  test "a failed attempt remains unsynced and a retry receives a fresh sequence" do
    article = media_article

    assert_raises(RuntimeError) do
      article.sync_to_search!(namespace: Namespace.new(error: "TP unavailable"),
        embedding_client: EmbeddingClient.new)
    end
    failed_sequence = article.reload.search_index_sequence
    assert_nil article.search_synced_at

    article.sync_to_search!(namespace: Namespace.new, embedding_client: EmbeddingClient.new)

    assert_operator article.reload.search_index_sequence, :>, failed_sequence
    assert article.search_synced_at.present?
  end

  test "warehouse records index themselves without creating a projection" do
    suffix = SecureRandom.hex(4)
    jurisdiction = Warehouse::Jurisdiction.create!(code: "SE-#{suffix}", name: "Search #{suffix}",
      slug: "search-#{suffix}", level: "federal", fiscal_year_start_month: 4, default_currency: "CAD")
    organization = Warehouse::Organization.create!(jurisdiction: jurisdiction,
      canonical_name: "Department #{suffix}", slug: "department-#{suffix}")
    record = Warehouse::FiscalExpenditure.create!(organization: organization, fiscal_year: "2024-25",
      vote_type: "operating", description: "Operations", actual_expenditure: 125_000)
    namespace = Namespace.new

    result = record.sync_to_search!(namespace:, embedding_client: EmbeddingClient.new)

    row = namespace.writes.sole.fetch(:upsert_rows).sole
    assert_equal "fiscal_expenditure:#{record.id}", row.fetch(:id)
    assert_equal "government_spending", row.fetch(:realm)
    assert_equal 125_000.0, row.fetch(:amount)
    assert_equal record.search_id, result.fetch(:upserted_ids).sole
    assert record.reload.search_synced_at.present?
    assert_equal record, Searchable.resolve(record.search_id)
  end

  test "unknown and malformed index ids do not resolve" do
    assert_nil Searchable.resolve("not-a-search-id")
    assert_nil Searchable.resolve("unknown_type:123")
  end

  private

  def media_article
    source = Search::Source.create!(name: "Searchable source #{SecureRandom.hex(4)}", realm: "media",
      strategy: "rss", url: "https://nationalpost.com/feed/", cadence_seconds: 300)
    Search::MediaArticle.new(source: source, external_key: SecureRandom.uuid,
      title: "Article #{SecureRandom.hex(3)}", content: "Whole article body", language: "en",
      realm_data: { "content_type" => "article", "publisher_name" => "National Post",
        "publisher_domain" => "nationalpost.com", "authors" => [], "word_count" => 3 }).tap(&:publish!)
  end
end
