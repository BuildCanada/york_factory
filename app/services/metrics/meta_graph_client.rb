module Metrics
  class MetaGraphClient
    DEFAULT_API_VERSION = "v24.0"
    BASE_URL = "https://graph.facebook.com"

    class Error < StandardError; end

    def initialize(access_token:, api_version: DEFAULT_API_VERSION, http: nil)
      raise ArgumentError, "Meta access token is required" if access_token.blank?

      @access_token = access_token
      @api_version = api_version.to_s.delete_prefix("/")
      @http = http
    end

    def get(path, params: {})
      response = client.get(url(path), params: params)
      if response.is_a?(HTTPX::ErrorResponse)
        raise Error, "Meta Graph API request failed: #{response.error.message}"
      end

      payload = JSON.parse(response.body.to_s)
      unless response.status.in?(200..299)
        message = payload.dig("error", "message") || "HTTP #{response.status}"
        raise Error, "Meta Graph API: #{message}"
      end

      payload
    rescue JSON::ParserError => error
      raise Error, "Meta Graph API returned invalid JSON: #{error.message}"
    rescue HTTPX::Error, SocketError, SystemCallError, Timeout::Error => error
      raise Error, "Meta Graph API request failed: #{error.message}"
    end

    def page_access_token(page_id)
      response = get("me/accounts", params: { fields: "id,access_token", limit: 100 })
      page = Array(response["data"]).find { |entry| entry["id"].to_s == page_id.to_s }
      token = page&.fetch("access_token", nil)
      raise Error, "Meta Graph API did not return an access token for Page #{page_id}" if token.blank?

      token
    end

    private

    def url(path)
      path = path.to_s
      return path if path.start_with?("https://", "http://")

      "#{BASE_URL}/#{@api_version}/#{path.delete_prefix('/')}"
    end

    def client
      @http || HTTPX.plugin(:auth).bearer_auth(@access_token)
    end
  end
end
