require "test_helper"

class Warehouse::SpendingAwardTest < ActiveJob::TestCase
  EmbeddingResult = Data.define(:vectors, :model, :usage)

  class FakeEmbeddingClient
    def embed_documents(_texts)
      EmbeddingResult.new(
        vectors: [ Array.new(1_024, 0.25) ],
        model: "test-embedding",
        usage: { "input_tokens" => 12 }
      )
    end
  end

  class FakeNamespace
    attr_reader :writes

    def initialize
      @writes = []
    end

    def write(**options)
      @writes << options
      { rows_affected: 1 }
    end
  end

  class UnexpectedEmbeddingClient
    def embed_documents(*)
      raise "non-canonical versions must not be embedded"
    end
  end

  setup do
    @source = Warehouse::Source.create!(
      name: "spending_award_model_test_#{SecureRandom.hex(4)}",
      url: "https://example.test/awards.csv",
      format: "csv"
    )
  end

  test "maps an award to the government spending search realm" do
    organization = Warehouse::Organization.create!(canonical_name: "Department of Testing")
    award = build_award(
      payer_organization: organization,
      payer_name: organization.canonical_name,
      recipient_name: "Example Recipient",
      program_name: "Example Program",
      province_code: "ON",
      country_code: "CA",
      metadata: { "project_lead_name" => "Ada Researcher" }
    )

    data = award.search_data

    assert_equal "government_spending", award.class.search_realm
    assert_equal "grant", data.fetch(:record_type)
    assert_equal [ organization.id ], data.dig(:ontology, "organization_ids")
    assert_equal [ "ON" ], data.dig(:ontology, "province_codes")
    assert_equal "Example Recipient", data.dig(:realm_data, "recipient_name")
    assert_equal 12_345.67, data.dig(:realm_data, "amount")
    assert_includes data.fetch(:content), "Ada Researcher"
  end

  test "does not enqueue per-record search synchronization" do
    assert_no_enqueued_jobs only: Search::SyncJob do
      build_award
    end
  end

  test "writes a complete searchable row" do
    award = build_award
    namespace = FakeNamespace.new

    award.sync_to_search!(namespace: namespace, embedding_client: FakeEmbeddingClient.new)

    row = namespace.writes.sole.fetch(:upsert_rows).sole
    assert_equal award.search_id, row.fetch(:id)
    assert_equal "government_spending", row.fetch(:realm)
    assert_equal "grant", row.fetch(:record_type)
    assert_equal @source.name, row.fetch(:dataset_key)
    assert_equal "Example Recipient", row.fetch(:recipient_name)
    assert_not_nil award.reload.search_synced_at
  end

  test "removes withdrawn awards from the search index" do
    award = build_award
    award.update!(state: "withdrawn")
    namespace = FakeNamespace.new

    award.sync_to_search!(namespace: namespace)

    write = namespace.writes.sole
    assert_equal [ award.search_id ], write.fetch(:deletes)
    assert_not_nil award.reload.search_synced_at
  end

  test "deletes an old canonical version without embedding and indexes only the new canonical version" do
    old_version = build_award(is_canonical: false)
    current_version = build_award(is_canonical: true)
    namespace = FakeNamespace.new

    old_version.sync_to_search!(
      namespace: namespace,
      embedding_client: UnexpectedEmbeddingClient.new
    )
    current_version.sync_to_search!(
      namespace: namespace,
      embedding_client: FakeEmbeddingClient.new
    )

    delete, upsert = namespace.writes
    assert_equal [ old_version.search_id ], delete.fetch(:deletes)
    assert_equal [ current_version.search_id ], upsert.fetch(:upsert_rows).pluck(:id)
    assert_not_nil old_version.reload.search_synced_at
    assert_not_nil current_version.reload.search_synced_at
  end

  private

  def build_award(**attributes)
    now = Time.current
    Warehouse::SpendingAward.create!({
      source: @source,
      external_key: SecureRandom.hex(8),
      award_type: "grant",
      title: "A useful public grant",
      description: "Supports useful work",
      recipient_name: "Example Recipient",
      program_name: "Example Program",
      fiscal_year: 2025,
      occurred_at: Time.zone.parse("2025-04-01"),
      amount: 12_345.67,
      first_seen_at: now,
      last_seen_at: now
    }.merge(attributes))
  end
end
