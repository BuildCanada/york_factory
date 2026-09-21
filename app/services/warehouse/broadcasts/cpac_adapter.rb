require "json"

module Warehouse
  module Broadcasts
    class CpacAdapter
      LISTING_URL = "https://www.cpac.ca/api/1/services/item-list.json?localId=%2Fsite%2Fcomponents%2Fcpac-item-lists%2Flivestreams.xml&removeCpacTv=false"
      SITE_URL = "https://www.cpac.ca"
      ALLOWED_HOSTS = %w[cpac.ca www.cpac.ca].freeze
      ALLOWED_HOST_SUFFIXES = %w[.cdn.vustreams.com].freeze
      CAPTION_EVIDENCE = "CPAC TV and parliamentary samples inspected 2026-09-21: A53 field 1 English, field 2 French; provider-specific mapping"

      Stream = Data.define(:external_id, :kind, :title_en, :title_fr, :description_en, :description_fr, :page_url_en, :page_url_fr, :manifest_url, :provider_state, :scheduled_start_at, :metadata)
      Track = Data.define(:track_key, :kind, :language, :role, :delivery, :parent_track_key, :playlist_url, :codec, :metadata)

      def initialize(http: HttpClient.new)
        @http = http
      end

      def discover
        response = @http.get(LISTING_URL, max_bytes: 2.megabytes, **host_policy)
        payload = JSON.parse(response.body)
        Array(payload["item"]).filter_map { |item| normalize_item(item) }
      rescue JSON::ParserError => error
        raise HttpClient::PermanentError, "invalid CPAC listing JSON: #{error.message}"
      end

      def tracks(manifest_url)
        response = @http.get(manifest_url, max_bytes: 2.megabytes, **host_policy)
        @manifest_snapshot = { body: response.body, content_type: response.content_type, url: response.url }
        master = Hls.parse(response.body, base_url: response.url)
        raise Hls::ParseError, "CPAC entry did not resolve to a master playlist" unless master.is_a?(Hls::Master)

        variant = select_variant(master.variants)
        tracks = [ Track.new(
          track_key: video_track_key(variant), kind: "video", language: "und", role: "main", delivery: "separate",
          parent_track_key: nil, playlist_url: variant.uri, codec: video_codec(variant.codecs),
          metadata: { "width" => variant.width, "height" => variant.height, "bandwidth" => variant.bandwidth, "source_attributes" => variant.attributes }
        ) ]

        audio_renditions(master, variant).each do |rendition|
          language, role = audio_language_and_role(rendition)
          tracks << Track.new(
            track_key: "audio:#{rendition.group_id}:#{language}:#{rendition_identity(rendition)}", kind: "audio", language:, role:, delivery: "separate",
            parent_track_key: nil, playlist_url: rendition.uri, codec: "mp4a.40.2",
            metadata: { "name" => rendition.name, "group_id" => rendition.group_id, "default" => rendition.default, "source_attributes" => rendition.attributes }
          )
        end

        caption_renditions(master, variant).each do |rendition|
          [ [ 1, "en" ], [ 2, "fr" ] ].each do |field, language|
            tracks << Track.new(
              track_key: "captions:#{rendition.group_id}:field#{field}", kind: "captions", language:, role: "captions", delivery: "embedded",
              parent_track_key: video_track_key(variant), playlist_url: nil, codec: "eia_608",
              metadata: {
                "caption_field" => field, "extractor_input" => "a53cc", "instream_id" => rendition.instream_id,
                "group_id" => rendition.group_id, "mapping_scope" => "cpac", "mapping_evidence" => CAPTION_EVIDENCE,
                "source_attributes" => rendition.attributes
              }
            )
          end
        end
        tracks
      end

      attr_reader :manifest_snapshot

      private

      def normalize_item(item)
        return if ActiveModel::Type::Boolean.new.cast(item["testStream"])
        return if item["episodeId"].blank? || item["videoUrl"].blank?

        type = item["type"].to_s
        kind = type == "cpactv" ? "continuous" : "event"
        Stream.new(
          external_id: item.fetch("episodeId"), kind:, title_en: item["title_en_t"], title_fr: item["title_fr_t"],
          description_en: item["description_en_t"], description_fr: item["description_fr_t"],
          page_url_en: page_url(item["url_en_s"]), page_url_fr: page_url(item["url_fr_s"]),
          manifest_url: item.fetch("videoUrl"), provider_state: type,
          scheduled_start_at: kind == "event" ? parse_time(item["liveDateTime"]) : nil,
          metadata: item.slice("program_id", "category_en_t", "category_fr_t", "categoryURL_en_s", "categoryURL_fr_s", "videoDuration", "lastDateModified", "image_en_s", "image_fr_s")
            .merge("cpac_type" => type, "discovery_url" => LISTING_URL)
        )
      end

      def select_variant(variants)
        eligible = variants.select { |variant| variant.height.positive? && variant.height <= 720 }
        raise Hls::UnsupportedTransport, "master playlist has no video rendition at or below 720p" if eligible.empty?

        eligible.max_by { |variant| [ variant.height, variant.bandwidth ] }
      end

      def audio_renditions(master, variant)
        master.renditions.select do |rendition|
          rendition.type == "audio" && rendition.group_id == variant.audio_group && rendition.uri.present? &&
            %w[en eng fr fra fre mul].include?(rendition.language.to_s.downcase)
        end
      end

      def caption_renditions(master, variant)
        master.renditions.select { |rendition| rendition.type == "closed-captions" && rendition.group_id == variant.captions_group }
      end

      def audio_language_and_role(rendition)
        case rendition.language.to_s.downcase
        when "en", "eng" then [ "en", "interpreted" ]
        when "fr", "fra", "fre" then [ "fr", "interpreted" ]
        else [ "mul", "floor" ]
        end
      end

      def video_track_key(variant)
        uri = URI.parse(variant.uri)
        source_identity = Digest::SHA256.hexdigest([ uri.host, uri.path ].join("|"))[0, 12]
        "video:#{variant.height}p:#{source_identity}"
      end

      def video_codec(codecs)
        codecs.to_s.split(",").find { |codec| codec.strip.start_with?("avc", "hvc", "hev") }&.strip
      end

      def rendition_identity(rendition)
        uri = URI.parse(rendition.uri)
        source_identity = [ rendition.name, uri.host, uri.path ].join("|")
        Digest::SHA256.hexdigest(source_identity).first(12)
      end

      def page_url(value)
        value.present? ? URI.join(SITE_URL, value).to_s : nil
      end

      def parse_time(value)
        Time.iso8601(value).utc if value.present?
      rescue ArgumentError
        nil
      end

      def host_policy
        { allowed_hosts: ALLOWED_HOSTS, allowed_host_suffixes: ALLOWED_HOST_SUFFIXES }
      end
    end
  end
end
