require "test_helper"

class Search::Embedding::AzureCohereClientTest < ActiveSupport::TestCase
  Response = Data.define(:status, :headers, :body)

  class FakeHttp
    attr_reader :requests

    def initialize(*responses)
      @responses = responses
      @requests = []
    end

    def post(url, **request)
      @requests << request.merge(url: url)
      response = @responses.shift
      raise response if response.is_a?(Exception)

      response
    end
  end

  setup do
    @vector = Array.new(1_024, 0.125)
  end

  test "embeds documents through the Azure OpenAI-compatible endpoint" do
    http = FakeHttp.new(success_response([ @vector ], request_id: "request-123"))
    client = build_client(http: http)

    result = client.embed_documents([ "A whole article" ])

    request = http.requests.fetch(0)
    assert_equal "https://example.openai.azure.com/openai/v1/embeddings", request[:url]
    assert_equal "test-key", request[:headers]["api-key"]
    assert_equal "pass-through", request[:headers]["extra-parameters"]
    assert_equal({
      model: "embed-v-4-0",
      input: [ "A whole article" ],
      dimensions: 1_024,
      encoding_format: "float",
      input_type: "document"
    }, JSON.parse(request[:body], symbolize_names: true))
    assert_equal [ @vector ], result.vectors
    assert_equal "document", result.input_type
    assert_equal "request-123", result.request_id
    assert_equal({ "prompt_tokens" => 12 }, result.usage)
  end

  test "uses query input type for search text" do
    http = FakeHttp.new(success_response([ @vector ]))

    build_client(http: http).embed_queries([ "offshore wind" ])

    assert_equal "query", JSON.parse(http.requests.dig(0, :body)).fetch("input_type")
  end

  test "can omit input type for endpoints that reject provider extensions" do
    http = FakeHttp.new(success_response([ @vector ]))

    build_client(http: http, include_input_type: false).embed_documents([ "article" ])

    refute JSON.parse(http.requests.dig(0, :body)).key?("input_type")
  end

  test "sorts batched vectors by response index" do
    other_vector = Array.new(1_024, 0.25)
    response = response(
      status: 200,
      body: {
        data: [
          { index: 1, embedding: other_vector },
          { index: 0, embedding: @vector }
        ]
      }
    )

    result = build_client(http: FakeHttp.new(response)).embed_documents([ "one", "two" ])

    assert_equal [ @vector, other_vector ], result.vectors
  end

  test "retries transient responses and succeeds" do
    sleeps = []
    http = FakeHttp.new(
      response(status: 429, body: { error: "rate limited" }, headers: { "retry-after" => "0.01" }),
      success_response([ @vector ])
    )

    result = build_client(http: http, sleeper: ->(seconds) { sleeps << seconds }).embed_documents([ "article" ])

    assert_equal [ @vector ], result.vectors
    assert_equal 2, http.requests.length
    assert_equal [ 0.01 ], sleeps
  end

  test "does not include a response body in raised API errors" do
    http = FakeHttp.new(response(
      status: 422,
      body: { error: { message: "invalid: secret article body" } },
      headers: { "apim-request-id" => "request-422" }
    ))

    error = assert_raises(Search::Embedding::AzureCohereClient::ResponseError) do
      build_client(http: http).embed_documents([ "secret article body" ])
    end

    assert_equal 422, error.status
    assert_equal "request-422", error.request_id
    refute_includes error.message, "secret article body"
  end

  test "rejects malformed vector dimensions" do
    http = FakeHttp.new(success_response([ [ 0.1, 0.2 ] ]))

    assert_raises(Search::Embedding::AzureCohereClient::ResponseFormatError) do
      build_client(http: http).embed_documents([ "article" ])
    end
  end

  test "rejects empty and oversized batches before a network call" do
    http = FakeHttp.new
    client = build_client(http: http)

    assert_raises(ArgumentError) { client.embed_documents([]) }
    assert_raises(ArgumentError) { client.embed_documents([ "" ]) }
    assert_raises(ArgumentError) { client.embed_documents(Array.new(97, "article")) }
    assert_empty http.requests
  end

  private

  def build_client(http:, **options)
    Search::Embedding::AzureCohereClient.new(
      endpoint: "https://example.openai.azure.com/openai/v1",
      api_key: "test-key",
      model: "embed-v-4-0",
      http: http,
      max_retries: 1,
      **options
    )
  end

  def success_response(vectors, request_id: nil)
    response(
      status: 200,
      body: {
        data: vectors.each_with_index.map { |vector, index| { index: index, embedding: vector } },
        model: "embed-v-4-0",
        usage: { prompt_tokens: 12 }
      },
      headers: request_id ? { "apim-request-id" => request_id } : {}
    )
  end

  def response(status:, body:, headers: {})
    Response.new(
      status: status,
      headers: headers,
      body: JSON.generate(body)
    )
  end
end
