module Webflow
  class Client
    BASE_URL = "https://api.webflow.com/v2"
    PAGE_SIZE = 100

    class Error < StandardError; end

    def initialize(api_token)
      @api_token = api_token
    end

    def get(path)
      uri = URI("#{BASE_URL}#{path}")
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
        req = Net::HTTP::Get.new(uri)
        req["Authorization"] = "Bearer #{@api_token}"
        http.request(req)
      end

      raise Error, "Webflow API #{response.code}: #{response.body}" unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    end

    def fetch_all_items(collection_id)
      items = []
      offset = 0

      loop do
        data = get("/collections/#{collection_id}/items?limit=#{PAGE_SIZE}&offset=#{offset}")
        items.concat(data["items"] || [])
        offset += PAGE_SIZE
        break if items.size >= data.dig("pagination", "total").to_i
      end

      items
    end
  end
end
