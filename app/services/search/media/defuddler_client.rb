require "json"

module Search
  module Media
    class DefuddlerClient
      MAX_RESPONSE_BYTES = 8.megabytes

      class Error < StandardError; end
      class ConfigurationError < Error; end
      class InvalidResponse < Error; end

      def initialize(
        base_url: nil,
        api_key: Search::ProviderConfig.defuddler_api_key,
        http: HTTPX.with(timeout: { connect_timeout: 5, operation_timeout: 45 }),
        resolver: Resolv.method(:getaddresses)
      )
        @base_url = base_url.presence || Search::ProviderConfig.defuddler_base_url
        @api_key = api_key
        @http = http
        @resolver = resolver
      end

      def convert(url:, language: nil)
        safe_url = SafeUrl.validate_public!(url, resolver: @resolver)
        response = @http.post(
          endpoint,
          headers: request_headers,
          body: JSON.generate({ url: safe_url, language: language }.compact)
        )
        unless response.respond_to?(:status)
          raise TransientError, response.error.message
        end

        status = response.status.to_i
        if status == 408 || status == 429 || status >= 500
          raise TransientError.new("Defuddler returned HTTP #{status}", status: status)
        end
        raise Error, "Defuddler returned HTTP #{status}" unless status.between?(200, 299)

        body = response.body.to_s
        raise InvalidResponse, "Defuddler response exceeded #{MAX_RESPONSE_BYTES} bytes" if body.bytesize > MAX_RESPONSE_BYTES

        payload = JSON.parse(body)
        raise InvalidResponse, "Defuddler response must be a JSON object" unless payload.is_a?(Hash)

        payload
      rescue JSON::ParserError => error
        raise InvalidResponse, "Defuddler returned invalid JSON: #{error.message}"
      rescue HTTPX::Error, SocketError, SystemCallError, Timeout::Error => error
        raise TransientError, error.message
      end

      private

      def endpoint
        uri = URI.parse(@base_url.to_s)
        unless uri.is_a?(URI::HTTP) && uri.host.present?
          raise ConfigurationError, "DEFUDDLER_BASE_URL must be an HTTP(S) URL"
        end

        path = [ uri.path.to_s.delete_suffix("/"), "api/convert" ].reject(&:blank?).join("/")
        uri.path = path.start_with?("/") ? path : "/#{path}"
        uri.query = nil
        uri.fragment = nil
        uri.to_s
      rescue URI::Error => error
        raise ConfigurationError, error.message
      end

      def request_headers
        {
          "Content-Type" => "application/json",
          "Accept" => "application/json"
        }.tap do |headers|
          headers["X-API-Key"] = @api_key if @api_key.present?
        end
      end
    end
  end
end
