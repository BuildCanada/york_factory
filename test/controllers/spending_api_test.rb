require "test_helper"

class SpendingApiTest < ActionDispatch::IntegrationTest
  class FakeNamespace
    attr_reader :queries

    def initialize(response)
      @response = response
      @queries = []
    end

    def query(**query)
      @queries << query
      @response
    end
  end

  test "proxies Turbopuffer searches and enforces the public spending scope" do
    provider_response = {
      rows: [ { id: "spending_cihr_awards:cihr-1", recipient_name: "University of Alberta" } ],
      aggregations: { payer_names: [ { value: "CIHR", count: 1 } ] },
      billing: { billable_logical_bytes_queried: 42 },
      performance: { query_execution_ms: 3 }
    }
    namespace = FakeNamespace.new(provider_response)
    client_filter = [ "fiscal_year", "Gte", 2024 ]

    with_namespace(namespace) do
      post "/api/v1/spending/search", params: {
        rank_by: [ "content", "BM25", "health research" ],
        aggregate_by: { payer_names: { top_k: 20 } },
        include_attributes: [ "id", "recipient_name" ],
        filters: client_filter,
        limit: 25
      }, as: :json
    end

    assert_response :success
    assert_equal provider_response.deep_stringify_keys, response.parsed_body

    query = namespace.queries.sole
    assert_equal [ "content", "BM25", "health research" ], query.fetch(:rank_by)
    assert_equal({ payer_names: { top_k: 20 } }, query.fetch(:aggregate_by))
    assert_equal [ "id", "recipient_name" ], query.fetch(:include_attributes)
    assert_equal 25, query.fetch(:limit)
    assert_equal({ level: :strong }, query.fetch(:consistency))
    assert_equal [ "And", [
      [ "realm", "Eq", "government_spending" ],
      [ "visibility", "Eq", "public" ],
      client_filter
    ] ], query.fetch(:filters)
  end

  test "rejects provider namespace overrides and legacy search parameters" do
    namespace = FakeNamespace.new({ rows: [] })

    with_namespace(namespace) do
      post "/api/v1/spending/search", params: { namespace: "another", q: "health" }, as: :json
    end

    assert_response :unprocessable_entity
    assert_equal "invalid_search", response.parsed_body.fetch("error")
    assert_includes response.parsed_body.fetch("details"), "namespace"
    assert_empty namespace.queries
  end

  test "caps the number of returned rows" do
    namespace = FakeNamespace.new({ rows: [] })

    with_namespace(namespace) do
      post "/api/v1/spending/search", params: { limit: 251 }, as: :json
    end

    assert_response :unprocessable_entity
    assert_includes response.parsed_body.fetch("details"), "between 0 and 250"
    assert_empty namespace.queries
  end

  test "looks up awards with source names as dataset slugs" do
    award = create_award("spending_cihr_awards", external_key: "cihr-1")

    get "/api/v1/spending/databases/spending_cihr_awards/awards/cihr-1"

    assert_response :success
    assert_equal award.search_id, response.parsed_body.dig("data", "id")
    assert_equal "canada-spends.db/spending_cihr_awards", response.parsed_body.dig("data", "type")
    assert_equal "spending_cihr_awards", response.parsed_body.dig("data", "source", "name")
  end

  test "does not expose unknown sources or withdrawn awards" do
    award = create_award("spending_nserc_awards", external_key: "nserc-1")

    get "/api/v1/spending/databases/unknown/awards/nserc-1"
    assert_response :not_found

    award.update!(state: "withdrawn")
    get "/api/v1/spending/databases/spending_nserc_awards/awards/nserc-1"
    assert_response :not_found
  end

  private

  def with_namespace(namespace)
    original = Search.method(:turbopuffer_namespace)
    Search.define_singleton_method(:turbopuffer_namespace) { namespace }
    yield
  ensure
    Search.define_singleton_method(:turbopuffer_namespace, original)
  end

  def create_award(source_name, external_key:)
    source = Warehouse::Source.create!(
      name: source_name,
      url: "https://example.test/#{source_name}",
      format: "csv",
      attribution: "Government of Canada",
      license: "Open Government Licence"
    )
    now = Time.current
    Warehouse::SpendingAward.create!(
      source:,
      external_key:,
      award_type: "grant",
      title: "Health research",
      description: "Research abstract",
      recipient_name: "University of Alberta",
      program_name: "Project Grant",
      fiscal_year: 2024,
      occurred_at: Time.zone.parse("2024-04-01"),
      amount: 50_000,
      currency: "CAD",
      first_seen_at: now,
      last_seen_at: now
    )
  end
end
