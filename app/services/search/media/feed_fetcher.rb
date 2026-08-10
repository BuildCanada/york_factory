require "rss"
require "time"

module Search
  module Media
    class FeedFetcher
      Result = Data.define(:entries, :etag, :last_modified, :status, :url, :response_checksum)

      MAX_RESPONSE_BYTES = 5.megabytes
      MAX_REDIRECTS = 3
      USER_AGENT = "BuildCanadaBot"
      REDIRECT_STATUSES = [ 301, 302, 303, 307, 308 ].freeze
      DEFAULT_HTTP_OPTIONS = {
        ssl: { alpn_protocols: [ "http/1.1" ] },
        timeout: { connect_timeout: 5, operation_timeout: 20 }
      }.freeze

      class Error < StandardError; end
      class TransientError < Error; end
      class RateLimited < TransientError
        attr_reader :retry_after

        def initialize(message, retry_after: nil)
          @retry_after = retry_after
          super(message)
        end
      end
      class PermanentError < Error; end
      class InvalidFeed < PermanentError; end

      def initialize(http: nil, resolver: Resolv.method(:getaddresses), max_redirects: MAX_REDIRECTS)
        @http = http
        @resolver = resolver
        @max_redirects = max_redirects
      end

      def call(url:, etag: nil, last_modified: nil, allow_http: false)
        response = fetch(
          url,
          headers: conditional_headers(etag:, last_modified:),
          allow_http: allow_http
        )

        return result(response, entries: []) if response.fetch(:status) == 304
        unless response.fetch(:status).between?(200, 299)
          status = response.fetch(:status)
          if status == 429
            raise RateLimited.new(
              "feed returned HTTP 429",
              retry_after: retry_after_seconds(response.fetch(:headers)["retry-after"])
            )
          end

          error_class = status == 408 || status >= 500 ? TransientError : PermanentError
          raise error_class, "feed returned HTTP #{status}"
        end

        entries = parse_entries(response.fetch(:body))
        raise InvalidFeed, "response was not a recognized RSS or Atom feed" if entries.empty?

        result(response, entries: entries)
      end

      private

      def fetch(url, headers:, allow_http:)
        current_url = url

        (@max_redirects + 1).times do |redirect_count|
          safe_url = SafeUrl.validate_public!(current_url, resolver: @resolver, allow_http: allow_http)
          response = http_client.get(safe_url, headers: headers)
          unless response.respond_to?(:status)
            raise TransientError, response.error.message
          end

          status = response.status.to_i
          if REDIRECT_STATUSES.include?(status)
            raise PermanentError, "too many redirects" if redirect_count == @max_redirects

            location = response.headers["location"]
            raise PermanentError, "redirect response omitted Location" if location.blank?

            current_url = URI.join(safe_url, location).to_s
            next
          end

          body = response.body.to_s
          if body.bytesize > MAX_RESPONSE_BYTES
            raise PermanentError, "feed response exceeded #{MAX_RESPONSE_BYTES} bytes"
          end

          return {
            status: status,
            headers: response.headers.to_h.transform_keys { |key| key.to_s.downcase },
            body: body,
            url: safe_url
          }
        end
      rescue SafeUrl::Invalid, URI::Error => error
        raise PermanentError, error.message
      rescue HTTPX::Error, SocketError, SystemCallError, Timeout::Error => error
        raise TransientError, error.message
      end

      def http_client
        # Use a fresh default session for each hop. Some publisher CDNs close
        # the first response without leaving a reusable connection.
        @http || HTTPX.with(**DEFAULT_HTTP_OPTIONS)
      end

      def parse_entries(body)
        feed = RSS::Parser.parse(body, false)
        return feed.items.filter_map { |item| normalize(item) } if feed

        []
      rescue RSS::Error
        recover_entries(body)
      end

      # Some publisher feeds contain malformed markup inside descriptions. A
      # non-networked recovery parse keeps discovery working while Defuddler
      # remains authoritative for article content and metadata.
      def recover_entries(body)
        document = Nokogiri::XML(body) { |config| config.recover.nonet }
        document.xpath("//*[local-name()='item' or local-name()='entry']").filter_map do |item|
          normalize_recovered(item)
        end
      rescue Nokogiri::XML::SyntaxError => error
        raise Error, "invalid feed: #{error.message}"
      end

      def normalize_recovered(item)
        link = item.at_xpath("./*[local-name()='link']")
        url = link&.[]("href").presence || link&.text.to_s.presence
        return if url.blank?

        {
          "url" => SafeUrl.canonicalize(url),
          "guid" => recovered_text(item, "guid", "id"),
          "title" => recovered_text(item, "title"),
          "summary" => recovered_text(item, "description", "summary"),
          "author" => recovered_text(item, "creator", "author"),
          "published_at" => recovered_text(item, "pubDate", "published", "updated", "date")
        }
      rescue SafeUrl::Invalid
        nil
      end

      def recovered_text(item, *names)
        expression = names.map { |name| "local-name()='#{name}'" }.join(" or ")
        item.at_xpath("./*[#{expression}]")&.text.to_s.presence
      end

      def conditional_headers(etag:, last_modified:)
        { "User-Agent" => USER_AGENT }.tap do |headers|
          headers["If-None-Match"] = etag if etag.present?
          headers["If-Modified-Since"] = last_modified if last_modified.present?
          headers["Accept"] = "application/atom+xml, application/rss+xml, application/xml, text/xml"
        end
      end

      def retry_after_seconds(value)
        return if value.blank?

        seconds = Integer(value, exception: false)
        return seconds if seconds && seconds >= 0

        delay = Time.httpdate(value) - Time.current
        delay.ceil if delay.positive?
      rescue ArgumentError
        nil
      end

      def result(response, entries:)
        Result.new(
          entries: entries,
          etag: response.fetch(:headers)["etag"],
          last_modified: response.fetch(:headers)["last-modified"],
          status: response.fetch(:status),
          url: response.fetch(:url),
          response_checksum: Digest::SHA256.hexdigest(response.fetch(:body))
        )
      end

      def normalize(item)
        url = item_link(item)
        return if url.blank?

        {
          "url" => SafeUrl.canonicalize(url),
          "guid" => value(item, :guid)&.to_s,
          "title" => value(item, :title)&.to_s,
          "summary" => (value(item, :description) || value(item, :summary))&.to_s,
          "author" => (value(item, :dc_creator) || value(item, :author))&.to_s,
          "published_at" => (value(item, :pubDate) || value(item, :published) || value(item, :updated) || value(item, :dc_date))&.to_s
        }
      rescue SafeUrl::Invalid
        nil
      end

      def item_link(item)
        link = value(item, :link)
        link = link.href if link.respond_to?(:href)
        link.to_s.presence
      end

      def value(item, method)
        item.public_send(method) if item.respond_to?(method)
      end
    end
  end
end
