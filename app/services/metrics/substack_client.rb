module Metrics
  class SubstackClient
    class Error < StandardError; end
    class AuthenticationError < Error; end
    class NotFoundError < Error; end
    class RateLimitError < Error; end

    def initialize(base_url:, cookies: nil, http: nil)
      @base_url = base_url.to_s.delete_suffix("/")
      @cookies = cookies
      @http = http
      validate_base_url!
    end

    def get(path, params: {})
      response = if @http
        @http.get(url(path), params: params, headers: headers)
      else
        HTTPX.plugin(:follow_redirects).with(headers: headers).get(url(path), params: params)
      end
      parse_response(response)
    end

    def post_json(path, payload)
      response = if @http
        @http.post(url(path), json: payload, headers: headers)
      else
        HTTPX.plugin(:follow_redirects).with(headers: headers).post(url(path), json: payload)
      end
      parse_response(response)
    end

    def post_multipart(path, form:)
      response = if @http
        @http.post(url(path), form: form, headers: headers)
      else
        HTTPX.plugin(:follow_redirects).with(headers: headers).post(url(path), form: form)
      end
      parse_response(response)
    end

    private

    def parse_response(response)
      raise Error, "Substack request failed: #{response.error.message}" if response.is_a?(HTTPX::ErrorResponse)

      handle_response(response)
    rescue JSON::ParserError => error
      raise Error, "Substack returned invalid JSON: #{error.message}"
    rescue HTTPX::Error, SocketError, SystemCallError, Timeout::Error => error
      raise Error, "Substack request failed: #{error.message}"
    end

    def validate_base_url!
      uri = URI.parse(@base_url)
      raise ArgumentError, "Substack URL must use HTTPS" unless uri.is_a?(URI::HTTPS) && uri.host.present?
    rescue URI::InvalidURIError
      raise ArgumentError, "Substack URL is invalid"
    end

    def url(path)
      "#{@base_url}/#{path.to_s.delete_prefix('/')}"
    end

    def headers
      values = { "Accept" => "application/json", "User-Agent" => "BuildCanadaBot/1.0 (+#{PublicWebsite.url})" }
      values["Cookie"] = cookie_header if cookie_header.present?
      values
    end

    def cookie_header
      @cookie_header ||= case @cookies
      when String
        @cookies
      when Hash
        @cookies.map { |name, value| "#{name}=#{value}" }.join("; ")
      when Array
        @cookies.filter_map do |cookie|
          cookie = cookie.with_indifferent_access
          "#{cookie[:name]}=#{cookie[:value]}" if cookie[:name].present? && cookie[:value].present?
        end.join("; ")
      end
    end

    def handle_response(response)
      payload = JSON.parse(response.body.to_s)
      return payload if response.status.in?(200..299)

      error_payload = payload["error"]
      message = error_payload.is_a?(Hash) ? error_payload["message"] : error_payload
      message ||= "HTTP #{response.status}"
      error_class = case response.status
      when 401, 403 then AuthenticationError
      when 404 then NotFoundError
      when 429 then RateLimitError
      else Error
      end
      raise error_class, "Substack API: #{message}"
    end
  end
end
