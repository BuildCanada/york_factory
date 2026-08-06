module Search
  module Media
    class ArticleNormalizer
      class Invalid < StandardError; end

      def call(feed_entry:, extraction:, feed:)
        feed_entry = feed_entry.to_h.stringify_keys
        extraction = extraction.to_h.stringify_keys
        canonical_url = SafeUrl.canonicalize(extraction["url"].presence || feed_entry.fetch("url"))
        uri = URI.parse(canonical_url)
        publisher = Warehouse::MediaFeed.publisher_for(uri.host, feed:)
        raise Invalid, "unsupported media publisher: #{uri.host}" unless publisher

        title = clean_text(extraction["title"].presence || feed_entry["title"])
        content = clean_content(extraction["content"])
        raise Invalid, "article title is blank" if title.blank?
        raise Invalid, "article content is blank" if content.blank?

        summary = clean_text(extraction["description"].presence || feed_entry["summary"])
        language = normalize_language(extraction["language"].presence || feed.language)
        authors = normalize_authors(extraction["author"].presence || feed_entry["author"])

        {
          media_feed_id: feed.id,
          external_key: SafeUrl.digest(canonical_url),
          canonical_url: canonical_url,
          source_url: feed_entry["url"],
          title: title,
          summary: summary,
          content: content,
          language: language,
          published_at: parse_time(extraction["published"].presence || feed_entry["published_at"]),
          source_updated_at: parse_time(extraction["modified"]),
          ontology: {},
          realm_data: {
            "content_type" => normalize_content_type(extraction["type"]),
            "publisher_name" => publisher.fetch("name"),
            "publisher_domain" => publisher.fetch("domain"),
            "authors" => authors,
            "section" => clean_text(extraction["section"]),
            "word_count" => normalize_word_count(extraction["wordCount"], content),
            "image_url" => optional_url(extraction["image"]),
            "favicon_url" => optional_url(extraction["favicon"])
          }.compact,
          extraction_metadata: {
            "extractor" => "defuddler",
            "feed_guid" => feed_entry["guid"],
            "defuddler_domain" => extraction["domain"],
            "defuddler_source" => extraction["source"],
            "defuddler_site" => extraction["site"]
          }.compact
        }
      rescue KeyError => error
        raise Invalid, error.message
      end

      private

      def clean_text(value)
        return if value.blank?

        ActionView::Base.full_sanitizer.sanitize(value.to_s).squish.presence
      end

      def clean_content(value)
        value.to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "").delete("\u0000").strip.presence
      end

      def normalize_authors(value)
        Array(value).flatten.filter_map { |author| clean_text(author) }.uniq
      end

      def normalize_language(value)
        language = value.to_s.downcase.split(/[-_]/).first
        %w[en fr].include?(language) ? language : "und"
      end

      def normalize_content_type(value)
        type = value.to_s.downcase.tr(" -", "_")
        %w[article opinion editorial column live_blog].include?(type) ? type : "article"
      end

      def normalize_word_count(value, content)
        count = Integer(value, exception: false)
        count&.positive? ? count : content.scan(/\p{L}[\p{L}\p{M}'’-]*/).length
      end

      def optional_url(value)
        SafeUrl.canonicalize(value) if value.present?
      rescue SafeUrl::Invalid
        nil
      end

      def parse_time(value)
        return if value.blank?
        return value.in_time_zone if value.respond_to?(:in_time_zone)

        Time.zone.parse(value.to_s)
      rescue ArgumentError, TypeError
        nil
      end
    end
  end
end
