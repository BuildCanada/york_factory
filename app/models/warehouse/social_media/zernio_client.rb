module Warehouse::SocialMedia
  class ZernioClient
    BASE_URL = "https://zernio.com/api/v1"

    class Error < StandardError; end

    def initialize(api_key:)
      @api_key = api_key
    end

    def get(path, params: {})
      response = client.get("#{BASE_URL}#{path}", params: params)
      unless response.status.in?(200..299)
        raise Error, "Zernio returned HTTP #{response.status} for #{path}"
      end

      JSON.parse(response.body.to_s)
    rescue JSON::ParserError => e
      raise Error, "Zernio returned invalid JSON for #{path}: #{e.message}"
    end

    private

    def client
      @client ||= HTTPX.plugin(:auth).bearer_auth(@api_key)
    end
  end
end
