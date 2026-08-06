require "test_helper"

class Search::QueryRunnerTest < ActiveSupport::TestCase
  class FakeEmbeddingClient
    attr_reader :queries

    def initialize(vector)
      @vector = vector
      @queries = []
    end

    def embed_queries(queries)
      @queries.concat(queries)
      Search::Embedding::AzureCohereClient::Result.new(
        vectors: [ @vector ],
        model: "embed-v-4-0",
        input_type: "query",
        usage: {},
        request_id: "query-1"
      )
    end
  end

  class FakeNamespace
    attr_reader :requests
    attr_accessor :responses

    def initialize
      @requests = []
      @responses = []
    end

    def query(**arguments)
      requests << arguments
      responses.shift
    end
  end

  setup do
    @vector = Array.new(1_024, 0.1)
    @embedding_client = FakeEmbeddingClient.new(@vector)
    @namespace = FakeNamespace.new
    @runner = Search::QueryRunner.new(namespace: @namespace, embedding_client: @embedding_client)
  end

  test "passes compiled sequence and lexical membership filters to BM25" do
    @namespace.responses = [ provider_response(rows: [ { id: "doc-1", "$dist": 1.2 } ]) ]
    definition = media_definition(mode: "lexical", text: "housing policy", lexical_match: "phrase")

    result = @runner.call(definition, from_sequence: 10, to_sequence: 20, limit: 25)

    request = @namespace.requests.fetch(0)
    assert_equal [ "content_en", "BM25", "housing policy" ], request[:rank_by]
    assert_equal 25, request[:limit]
    assert_includes request[:filters].last, [ "index_sequence", "Gt", 10 ]
    assert_includes request[:filters].last, [ "index_sequence", "Lte", 20 ]
    assert_includes request[:filters].last,
      [ "content_en", "ContainsTokenSequence", "housing policy" ]
    assert_equal 1, result.query_count
    assert_empty @embedding_client.queries
  end

  test "embeds semantic query text and drops rows beyond the membership threshold" do
    @namespace.responses = [ provider_response(rows: [
      { id: "near", "$dist": 0.2 },
      { id: "far", "$dist": 0.7 },
      { id: "missing-distance" }
    ]) ]
    definition = media_definition(mode: "semantic", text: "health policy", semantic_max_distance: 0.3)

    result = @runner.call(definition)

    assert_equal [ "health policy" ], @embedding_client.queries
    request = @namespace.requests.fetch(0)
    assert_equal [ "embedding", "ANN", @vector ], request[:rank_by]
    assert_equal [ "near" ], result.rows.map { |row| row[:id] }
  end

  test "hybrid search thresholds semantic membership before client-side RRF" do
    @namespace.responses = [ provider_response(
      rows: [ { id: "lexical", "$dist": 4.0 }, { id: "both", "$dist": 2.0 } ],
      billing: { bytes: 10 }, performance: { server_ms: 3 }
    ), provider_response(
      rows: [ { id: "both", "$dist": 0.2 }, { id: "too-far", "$dist": 0.8 } ],
      billing: { bytes: 20 }, performance: { server_ms: 5 }
    ) ]
    definition = media_definition(mode: "hybrid", text: "energy policy", semantic_max_distance: 0.3)

    result = @runner.call(definition, limit: 10)

    assert_equal [ "both", "lexical" ], result.rows.map { |row| row[:id] }
    refute_includes result.rows.map { |row| row[:id] }, "too-far"
    assert_equal 2, result.query_count
    assert_equal({ bytes: 30 }, result.billing)
    assert_equal({ server_ms: 8 }, result.performance)
  end

  private

  def provider_response(rows:, billing: {}, performance: {})
    { rows:, billing:, performance: }
  end

  def media_definition(mode:, text: nil, semantic_max_distance: nil, lexical_match: nil)
    {
      version: 1,
      realm: "media",
      language: "en",
      mode: mode,
      text: text,
      semantic_max_distance: semantic_max_distance,
      lexical_match: lexical_match
    }.compact
  end
end
