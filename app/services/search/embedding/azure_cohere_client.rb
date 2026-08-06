require "json"
require "uri"

module Search
  module Embedding
    class AzureCohereClient
      DIMENSIONS = 1_024
      MAX_BATCH_SIZE = 96
      RETRYABLE_STATUS_CODES = [ 408, 409, 429 ].freeze

      Result = Data.define(:vectors, :model, :input_type, :usage, :request_id)

      class Error < StandardError; end
      class ConfigurationError < Error; end
      class ResponseError < Error
        attr_reader :status, :request_id

        def initialize(status:, request_id: nil)
          @status = status
          @request_id = request_id
          super("Azure Cohere embedding request failed (status=#{status}, request_id=#{request_id || 'unknown'})")
        end
      end

      class ResponseFormatError < Error; end

      def initialize(endpoint: nil, api_key: nil, model: nil, dimensions: DIMENSIONS,
        include_input_type: true, document_input_type: "document", query_input_type: "query",
        http: nil, open_timeout: 5, read_timeout: 60,
        max_retries: 3, sleeper: ->(seconds) { sleep(seconds) })
        @endpoint = endpoint || ProviderConfig.cohere_endpoint
        @api_key = api_key || ProviderConfig.cohere_api_key
        @model = model || ProviderConfig.cohere_model
        @dimensions = dimensions
        @include_input_type = include_input_type
        @document_input_type = document_input_type
        @query_input_type = query_input_type
        @http = http || HTTPX.with(timeout: { connect_timeout: open_timeout, operation_timeout: read_timeout })
        @max_retries = max_retries
        @sleeper = sleeper

        validate_configuration!
      end

      def embed_documents(texts)
        embed(texts, input_type: @document_input_type)
      end

      def embed_queries(texts)
        embed(texts, input_type: @query_input_type)
      end

      def embed(texts, input_type:)
        inputs = Array(texts)
        validate_inputs!(inputs)

        payload = {
          model: @model,
          input: inputs,
          dimensions: @dimensions,
          encoding_format: "float"
        }
        payload[:input_type] = input_type if @include_input_type

        response = with_retries do
          @http.post(
            embeddings_uri.to_s,
            headers: request_headers,
            body: JSON.generate(payload)
          )
        end

        parse_response(response, expected_count: inputs.length, input_type: input_type)
      end

      private

      def validate_configuration!
        raise ConfigurationError, "Azure Cohere endpoint is not configured" if @endpoint.blank?
        raise ConfigurationError, "Azure Cohere API key is not configured" if @api_key.blank?
        raise ConfigurationError, "Azure Cohere model is not configured" if @model.blank?
        raise ConfigurationError, "embedding dimensions must equal #{DIMENSIONS}" unless @dimensions == DIMENSIONS

        uri = URI.parse(@endpoint)
        raise ConfigurationError, "Azure Cohere endpoint must use HTTPS" unless uri.is_a?(URI::HTTPS)
      rescue URI::InvalidURIError
        raise ConfigurationError, "Azure Cohere endpoint is invalid"
      end

      def validate_inputs!(inputs)
        unless inputs.any? && inputs.length <= MAX_BATCH_SIZE
          raise ArgumentError, "texts must contain between 1 and #{MAX_BATCH_SIZE} items"
        end
        raise ArgumentError, "embedding inputs must be non-empty strings" unless inputs.all? { |text| text.is_a?(String) && text.present? }
      end

      def embeddings_uri
        base = @endpoint.delete_suffix("/")
        URI.parse(base.end_with?("/embeddings") ? base : "#{base}/embeddings")
      end

      def request_headers
        {
          "Content-Type" => "application/json",
          "Accept" => "application/json",
          "api-key" => @api_key,
          # Azure model inference accepts provider-specific request fields only
          # when this header permits them. It is harmless when input_type is off.
          "extra-parameters" => "pass-through"
        }
      end

      def with_retries
        attempts = 0

        begin
          response = yield
          return response unless retryable_status?(response.status) && attempts < @max_retries

          attempts += 1
          @sleeper.call(retry_delay(attempts, response.headers))
        rescue HTTPX::Error, EOFError, IOError, SocketError, SystemCallError
          raise if attempts >= @max_retries

          attempts += 1
          @sleeper.call(retry_delay(attempts, {}))
          retry
        end while true
      end

      def retryable_status?(status)
        RETRYABLE_STATUS_CODES.include?(status) || status >= 500
      end

      def retry_delay(attempt, headers)
        retry_after = headers["retry-after"].to_f
        return [ retry_after, 30 ].min if retry_after.positive?

        (0.25 * (2**(attempt - 1))) + (rand * 0.1)
      end

      def parse_response(response, expected_count:, input_type:)
        unless response.status.between?(200, 299)
          raise ResponseError.new(status: response.status, request_id: request_id(response.headers))
        end

        body = JSON.parse(response.body)
        rows = body.fetch("data").sort_by { |row| row.fetch("index") }
        vectors = rows.map { |row| row.fetch("embedding") }
        unless vectors.length == expected_count && vectors.all? { |vector| valid_vector?(vector) }
          raise ResponseFormatError, "Azure Cohere returned an unexpected embedding shape"
        end

        Result.new(
          vectors: vectors,
          model: body["model"] || @model,
          input_type: input_type,
          usage: body["usage"] || {},
          request_id: request_id(response.headers)
        )
      rescue JSON::ParserError, KeyError, TypeError
        raise ResponseFormatError, "Azure Cohere returned an invalid response"
      end

      def valid_vector?(vector)
        vector.is_a?(Array) && vector.length == @dimensions && vector.all? { |value| value.is_a?(Numeric) && value.finite? }
      end

      def request_id(headers)
        normalized = headers.respond_to?(:to_h) ? headers.to_h : headers
        normalized["apim-request-id"] || normalized["x-request-id"] || normalized["x-ms-request-id"]
      end
    end
  end
end
