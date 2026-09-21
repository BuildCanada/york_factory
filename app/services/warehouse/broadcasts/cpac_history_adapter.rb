require "date"
require "nokogiri"

module Warehouse
  module Broadcasts
    class CpacHistoryAdapter
      SEARCH_URL = "https://www.cpac.ca/search"
      EPISODE_URL = "https://www.cpac.ca/episode"
      MAX_PAGE_BYTES = 5.megabytes
      RESULTS_PER_PAGE = 20
      ARCHIVE_SUFFIX = ":archive"
      UUID_PATTERN = /\A[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i

      Page = Data.define(:entries, :errors, :page, :total, :next_page, :listing_url)

      def initialize(http: HttpClient.new, media_adapter: nil)
        @http = http
        @media_adapter = media_adapter || CpacAdapter.new(http:)
      end

      # CPAC's public archive date filters are inclusive calendar dates. Results
      # are server-rendered and currently contain 20 entries per page.
      def list(start_date:, end_date:, page: 1)
        start_date = coerce_date(start_date, name: "start_date")
        end_date = coerce_date(end_date, name: "end_date")
        raise ArgumentError, "end_date must be on or after start_date" if end_date < start_date

        page = coerce_page(page)

        listing_url = search_url(start_date:, end_date:, page:)
        response = get_page(listing_url)
        document = Nokogiri::HTML5(response.body)
        result_urls = document.css("#search-result-list-main .list-main__item").filter_map do |item|
          href = item.at_css(".list-main__title a[href*='id=']")&.[]("href")
          URI.join(CpacAdapter::SITE_URL, href).to_s if href.present?
        end.uniq
        total = parse_total(document)
        if total.positive? && result_urls.empty?
          raise HttpClient::PermanentError, "CPAC search reported results but exposed no episode links"
        end

        entries = []
        errors = []
        result_urls.each do |url|
          entries << stream_from_page(get_page(url), discovery_url: listing_url)
        rescue HttpClient::PermanentError => error
          errors << { "url" => url, "external_id" => episode_id_from_url(url), "error" => error.message }
        end

        Page.new(
          entries:,
          errors:,
          page:,
          total:,
          next_page: page * RESULTS_PER_PAGE < total ? page + 1 : nil,
          listing_url:
        )
      end

      def find(external_id)
        id = canonical_external_id(external_id)

        response = get_page("#{EPISODE_URL}?#{URI.encode_www_form(id:)}")
        stream_from_page(response, discovery_url: response.url)
      end

      def tracks(manifest_url)
        @media_adapter.tracks(manifest_url)
      end

      def manifest_snapshot
        @media_adapter.manifest_snapshot
      end

      private

      def search_url(start_date:, end_date:, page:)
        query = URI.encode_www_form(
          startDate: start_date.iso8601,
          endDate: end_date.iso8601,
          page:,
          order: "desc",
          type: "videos"
        )
        "#{SEARCH_URL}?#{query}"
      end

      def get_page(url)
        @http.get(url, max_bytes: MAX_PAGE_BYTES, allowed_hosts: CpacAdapter::ALLOWED_HOSTS)
      end

      def stream_from_page(response, discovery_url:)
        document = Nokogiri::HTML5(response.body)
        player = document.at_css("#video-page-video")
        raise HttpClient::PermanentError, "CPAC episode page omitted video metadata" unless player

        canonical_external_id = player["data-episodeid"]
        manifest_url = player["data-videourl"]
        unless canonical_external_id.to_s.match?(UUID_PATTERN) && manifest_url.present?
          raise HttpClient::PermanentError, "CPAC episode page omitted episode ID or VOD manifest"
        end
        external_id = "#{canonical_external_id}#{ARCHIVE_SUFFIX}"

        published_at = parse_time(player["data-livedatetime"])
        french_url = document.at_css(".language_picker[data-lan='fr']")&.[]("data-url")
        page_url_en = response.url
        page_url_fr = URI.join(CpacAdapter::SITE_URL, french_url).to_s if french_url.present?

        CpacAdapter::Stream.new(
          external_id:,
          kind: "on_demand",
          title_en: player["data-title_en_t"],
          title_fr: player["data-title_fr_t"],
          description_en: player["data-description_en_t"],
          description_fr: player["data-description_fr_t"],
          page_url_en:,
          page_url_fr:,
          manifest_url:,
          provider_state: "on_demand",
          scheduled_start_at: nil,
          metadata: {
            "cpac_type" => player["data-type"],
            "category_en" => player["data-category_en_t"],
            "category_fr" => player["data-category_fr_t"],
            "category_url_en" => absolute_page_url(player["data-categoryurl_en_s"]),
            "category_url_fr" => absolute_page_url(player["data-categoryurl_fr_s"]),
            "image_en" => player["data-image_en_s"],
            "image_fr" => player["data-image_fr_s"],
            "video_duration" => player["data-videoduration"],
            "provider_published_at" => published_at&.iso8601(3),
            "provider_published_at_semantics" => "CPAC archive calendar date; use HLS program date time as the media timeline anchor",
            "last_date_modified" => parse_time(player["data-lastdatemodified"])&.iso8601(3),
            "canonical_external_id" => canonical_external_id,
            "historical_manifest_url" => manifest_url,
            "historical_discovery_url" => discovery_url
          }.compact
        )
      end

      def parse_total(document)
        text = document.at_css("#total-results")&.text.to_s
        match = text.match(/\bof\s+([\d,]+)/i)
        raise HttpClient::PermanentError, "CPAC search page omitted its result total" unless match

        Integer(match[1].delete(","))
      end

      def episode_id_from_url(url)
        Rack::Utils.parse_nested_query(URI.parse(url).query).fetch("id", nil)
      rescue URI::Error
        nil
      end

      def coerce_date(value, name:)
        value.is_a?(Date) ? value : Date.iso8601(value.to_s)
      rescue Date::Error
        raise ArgumentError, "#{name} must be an ISO 8601 date"
      end

      def coerce_page(value)
        page = Integer(value)
        raise ArgumentError, "page must be a positive integer" unless page.positive?

        page
      rescue ArgumentError, TypeError
        raise ArgumentError, "page must be a positive integer"
      end

      def canonical_external_id(value)
        id = value.to_s.delete_suffix(ARCHIVE_SUFFIX)
        raise ArgumentError, "external_id must be a CPAC episode UUID" unless id.match?(UUID_PATTERN)

        id
      end

      def parse_time(value)
        Time.iso8601(value).utc if value.present?
      rescue ArgumentError
        nil
      end

      def absolute_page_url(value)
        URI.join(CpacAdapter::SITE_URL, value).to_s if value.present?
      end
    end
  end
end
