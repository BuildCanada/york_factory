require "resolv"

module Warehouse
  module Broadcasts
    class HttpClient
      Response = Data.define(:body, :content_type, :url, :status)

      MAX_REDIRECTS = 3
      DEFAULT_MAX_BYTES = 20.megabytes
      REDIRECT_STATUSES = [ 301, 302, 303, 307, 308 ].freeze
      OPTIONS = {
        ssl: { alpn_protocols: [ "http/1.1" ] },
        timeout: { connect_timeout: 5, operation_timeout: 20 }
      }.freeze

      class Error < StandardError; end
      class TransientError < Error; end
      class PermanentError < Error; end

      def initialize(http: nil, resolver: Resolv.method(:getaddresses), max_redirects: MAX_REDIRECTS)
        @http = http
        @resolver = resolver
        @max_redirects = max_redirects
      end

      def get(url, max_bytes: DEFAULT_MAX_BYTES, headers: {}, allowed_hosts: nil, allowed_host_suffixes: nil)
        current_url = url

        (@max_redirects + 1).times do |redirect_count|
          safe_url = SafeUrl.validate_public!(current_url, resolver: @resolver)
          validate_host!(safe_url, allowed_hosts:, allowed_host_suffixes:)
          response = if @http
            client.get(safe_url, headers: headers)
          else
            client.get(safe_url, headers: headers, stream: true)
          end
          raise TransientError, response.error.message unless response.respond_to?(:status)

          body = stream_response?(response) ? read_bounded(response, max_bytes:) : nil

          status = response.status.to_i
          if REDIRECT_STATUSES.include?(status)
            raise PermanentError, "too many redirects" if redirect_count == @max_redirects

            location = response.headers["location"]
            raise PermanentError, "redirect omitted Location" if location.blank?

            current_url = URI.join(safe_url, location).to_s
            next
          end

          unless status.between?(200, 299)
            error_class = status.in?([ 408, 429 ]) || status >= 500 ? TransientError : PermanentError
            raise error_class, "HTTP #{status} for #{safe_url}"
          end

          range_header = headers.find { |key, _value| key.to_s.casecmp?("Range") }&.last
          if range_header && status != 206
            raise PermanentError, "server ignored byte range for #{safe_url}"
          end

          content_length = response.headers["content-length"].to_i
          raise PermanentError, "response exceeded #{max_bytes} bytes" if content_length > max_bytes
          body ||= read_bounded(response.body, max_bytes:)
          validate_range!(range_header, response.headers["content-range"], body) if range_header

          return Response.new(
            body: body,
            content_type: response.headers["content-type"].to_s.split(";").first.presence,
            url: safe_url,
            status: status
          )
        end
      rescue SafeUrl::Invalid, URI::Error => error
        raise PermanentError, error.message
      rescue HTTPX::HTTPError => error
        status = error.response.status.to_i
        error_class = status.in?([ 408, 429 ]) || status >= 500 ? TransientError : PermanentError
        raise error_class, "HTTP #{status} for #{current_url}"
      rescue HTTPX::Error, SocketError, SystemCallError, Timeout::Error => error
        raise TransientError, error.message
      end

      private

      def client
        @http || HTTPX.plugin(:stream).with(**OPTIONS)
      end

      def read_bounded(response_body, max_bytes:)
        return bounded_string(response_body.to_s, max_bytes:) unless response_body.respond_to?(:each)

        response_body.each.with_object(+"") do |chunk, body|
          body << chunk
          raise PermanentError, "response exceeded #{max_bytes} bytes" if body.bytesize > max_bytes
        end
      end

      def stream_response?(response)
        defined?(HTTPX::StreamResponse) && response.is_a?(HTTPX::StreamResponse)
      end

      def bounded_string(body, max_bytes:)
        raise PermanentError, "response exceeded #{max_bytes} bytes" if body.bytesize > max_bytes

        body
      end

      def validate_host!(url, allowed_hosts:, allowed_host_suffixes:)
        return if allowed_hosts.nil? && allowed_host_suffixes.nil?

        host = URI.parse(url).host.downcase
        exact = Array(allowed_hosts).map(&:downcase).include?(host)
        suffix = Array(allowed_host_suffixes).map(&:downcase).any? { |value| host.end_with?(value) && host != value.delete_prefix(".") }
        raise PermanentError, "host #{host} is not allowed" unless exact || suffix
      end

      def validate_range!(requested, returned, body)
        requested_match = requested.to_s.match(/\Abytes=(\d+)-(\d+)\z/)
        returned_match = returned.to_s.match(/\Abytes (\d+)-(\d+)\/(?:\d+|\*)\z/i)
        unless requested_match && returned_match && requested_match.captures == returned_match.captures
          raise PermanentError, "server returned a mismatched byte range"
        end

        expected_size = requested_match[2].to_i - requested_match[1].to_i + 1
        raise PermanentError, "byte range body length did not match Content-Range" unless body.bytesize == expected_size
      end
    end
  end
end
