class LumaService
  BASE_URL = "https://public-api.luma.com/v1".freeze

  def initialize(api_key = nil)
    @api_key = api_key || Rails.application.credentials.dig(:luma, :api_key)
    raise ArgumentError, "Luma API key is required (credentials luma.api_key)" if @api_key.blank?
  end

  def fetch_all_events(before: nil, after: nil, limit: 50)
    events = []
    cursor = nil

    loop do
      response = fetch_events_page(
        before: before,
        after: after,
        limit: limit,
        cursor: cursor
      )

      break unless response.is_a?(Net::HTTPSuccess)

      data = JSON.parse(response.body)
      events.concat(data["entries"] || [])

      break unless data["has_more"]
      cursor = data["next_cursor"]
    end

    events
  rescue StandardError => e
    Rails.logger.error "LumaService: Failed to fetch events - #{e.message}"
    []
  end

  def fetch_events_page(before: nil, after: nil, limit: 50, cursor: nil)
    params = {
      sort_column: "start_at",
      sort_direction: "desc",
      pagination_limit: limit
    }

    params[:before] = before.iso8601 if before.present?
    params[:after] = after.iso8601 if after.present?
    params[:pagination_cursor] = cursor if cursor.present?

    make_request("/calendar/list-events", params: params)
  end

  def fetch_event(event_id)
    response = make_request("/calendar/get-event/#{event_id}")
    return nil unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  rescue JSON::ParserError => e
    Rails.logger.error "LumaService: Failed to parse event response - #{e.message}"
    nil
  end

  def fetch_all_guests(event_api_id, approval_status: nil, limit: 50)
    guests = []
    cursor = nil

    loop do
      response = fetch_guests_page(
        event_api_id: event_api_id,
        approval_status: approval_status,
        limit: limit,
        cursor: cursor
      )

      break unless response.is_a?(Net::HTTPSuccess)

      data = JSON.parse(response.body)
      guests.concat(data["entries"] || [])

      break unless data["has_more"]
      cursor = data["next_cursor"]
    end

    guests
  rescue StandardError => e
    Rails.logger.error "LumaService: Failed to fetch guests for event #{event_api_id} - #{e.message}"
    []
  end

  def fetch_guests_page(event_api_id:, approval_status: nil, limit: 50, cursor: nil)
    params = {
      event_api_id: event_api_id,
      pagination_limit: limit,
      sort_column: "registered_at",
      sort_direction: "desc"
    }

    params[:approval_status] = approval_status if approval_status.present?
    params[:pagination_cursor] = cursor if cursor.present?

    make_request("/event/get-guests", params: params)
  end

  private

  def make_request(endpoint, params: {})
    uri = URI("#{BASE_URL}#{endpoint}")
    uri.query = URI.encode_www_form(params) if params.any?

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Get.new(uri)
    request["x-luma-api-key"] = @api_key
    request["Accept"] = "application/json"
    request["User-Agent"] = "Build Canada Hub/1.0"

    response = http.request(request)

    unless response.is_a?(Net::HTTPSuccess)
      Rails.logger.error "LumaService: API request failed - #{response.code} #{response.message}"
      Rails.logger.error "LumaService: Response body - #{response.body}" if response.body.present?
    end

    response
  rescue StandardError => e
    Rails.logger.error "LumaService: Request failed - #{e.message}"
    raise
  end
end
