module Warehouse
  module Broadcasts
    module Hls
      Rendition = Data.define(:type, :group_id, :name, :language, :default, :autoselect, :uri, :instream_id, :attributes)
      Variant = Data.define(:uri, :bandwidth, :average_bandwidth, :width, :height, :codecs, :audio_group, :captions_group, :attributes)
      Master = Data.define(:variants, :renditions)
      Segment = Data.define(
        :uri, :sequence, :duration, :starts_at, :ends_at, :anchor_source,
        :relative_start, :relative_end, :discontinuity, :discontinuity_sequence,
        :byte_range, :init_uri
      )
      Media = Data.define(:media_sequence, :discontinuity_sequence, :target_duration, :end_list, :segments, :timestamp_map)

      class ParseError < StandardError; end
      class UnsupportedTransport < ParseError; end

      module_function

      def parse(body, base_url:, timeline_anchor: nil)
        lines = normalized_lines(body)
        raise ParseError, "missing EXTM3U header" unless lines.first == "#EXTM3U"

        lines.any? { |line| line.start_with?("#EXT-X-STREAM-INF:") } ?
          parse_master(lines, base_url:) : parse_media(lines, base_url:, timeline_anchor:)
      end

      def parse_master(lines, base_url:)
        variants = []
        renditions = []
        pending_variant = nil

        lines.drop(1).each do |line|
          if line.start_with?("#EXT-X-MEDIA:")
            attrs = attributes(line.delete_prefix("#EXT-X-MEDIA:"))
            renditions << Rendition.new(
              type: attrs["TYPE"].to_s.downcase,
              group_id: attrs["GROUP-ID"],
              name: attrs["NAME"],
              language: attrs["LANGUAGE"],
              default: yes?(attrs["DEFAULT"]),
              autoselect: yes?(attrs["AUTOSELECT"]),
              uri: absolute_url(base_url, attrs["URI"]),
              instream_id: attrs["INSTREAM-ID"],
              attributes: attrs
            )
          elsif line.start_with?("#EXT-X-STREAM-INF:")
            pending_variant = attributes(line.delete_prefix("#EXT-X-STREAM-INF:"))
          elsif pending_variant && !line.start_with?("#")
            width, height = pending_variant["RESOLUTION"].to_s.split("x", 2).map(&:to_i)
            variants << Variant.new(
              uri: absolute_url(base_url, line),
              bandwidth: pending_variant["BANDWIDTH"].to_i,
              average_bandwidth: pending_variant["AVERAGE-BANDWIDTH"].to_i,
              width: width,
              height: height,
              codecs: pending_variant["CODECS"],
              audio_group: pending_variant["AUDIO"],
              captions_group: pending_variant["CLOSED-CAPTIONS"],
              attributes: pending_variant
            )
            pending_variant = nil
          end
        end

        raise ParseError, "master playlist has no variants" if variants.empty?
        Master.new(variants:, renditions:)
      end

      def parse_media(lines, base_url:, timeline_anchor: nil)
        media_sequence = integer_tag(lines, "#EXT-X-MEDIA-SEQUENCE:", default: 0)
        discontinuity_sequence = integer_tag(lines, "#EXT-X-DISCONTINUITY-SEQUENCE:", default: 0)
        target_duration = decimal_tag(lines, "#EXT-X-TARGETDURATION:")
        timestamp_map = lines.find { |line| line.start_with?("#USP-X-TIMESTAMP-MAP:") }&.delete_prefix("#USP-X-TIMESTAMP-MAP:")
        segments = []
        duration = nil
        current_time = nil
        anchor_source = nil
        discontinuity = false
        byte_range = nil
        next_byte_offset = nil
        init_uri = nil
        sequence = media_sequence
        current_discontinuity = discontinuity_sequence
        relative_offset = 0.0
        finite_playlist = lines.include?("#EXT-X-ENDLIST")

        lines.drop(1).each do |line|
          case line
          when /^#EXTINF:([^,]+)/
            duration = Float(Regexp.last_match(1))
            raise ParseError, "segment duration must be positive" unless duration.positive?
          when /^#EXT-X-KEY:(.+)$/
            method = attributes(Regexp.last_match(1))["METHOD"]
            raise UnsupportedTransport, "encrypted HLS is unsupported (#{method})" unless method == "NONE"
          when /^#EXT-X-PROGRAM-DATE-TIME:(.+)$/
            current_time = Time.iso8601(Regexp.last_match(1)).utc
            anchor_source = "program_date_time"
          when "#EXT-X-DISCONTINUITY"
            discontinuity = true
            current_discontinuity += 1
            current_time = nil
            anchor_source = nil
          when /^#EXT-X-BYTERANGE:(.+)$/
            byte_range = parse_byte_range(Regexp.last_match(1), implicit_offset: next_byte_offset)
          when /^#EXT-X-MAP:(.+)$/
            raise UnsupportedTransport, "fragmented MP4 HLS init maps are unsupported"
          else
            next if line.start_with?("#") || line.blank? || duration.nil?
            unless current_time
              raise ParseError, "segment #{sequence} has no provider timeline anchor" unless timeline_anchor
              unless finite_playlist
                raise ParseError, "publication-time fallback requires a finite VOD playlist"
              end

              current_time = timeline_anchor + relative_offset
              anchor_source = "publication_time_relative_offset"
            end

            ends_at = current_time + duration
            segments << Segment.new(
              uri: absolute_url(base_url, line), sequence:, duration:, starts_at: current_time,
              ends_at:, anchor_source:, relative_start: relative_offset,
              relative_end: relative_offset + duration, discontinuity:,
              discontinuity_sequence: current_discontinuity,
              byte_range:, init_uri:
            )
            next_byte_offset = byte_range && byte_range.fetch("offset") + byte_range.fetch("length")
            current_time = ends_at
            anchor_source = anchor_source == "publication_time_relative_offset" ?
              anchor_source : "program_date_time_derived"
            relative_offset += duration
            sequence += 1
            duration = nil
            discontinuity = false
            byte_range = nil
          end
        end

        Media.new(
          media_sequence:, discontinuity_sequence:, target_duration:,
          end_list: lines.include?("#EXT-X-ENDLIST"), segments:, timestamp_map:
        )
      rescue ArgumentError => error
        raise ParseError, error.message
      end

      def attributes(value)
        value.scan(/([A-Z0-9-]+)=((?:"(?:[^"\\]|\\.)*")|[^,]*)/).to_h.transform_values do |raw|
          raw.start_with?("\"") ? raw[1...-1].gsub(/\\(["\\])/, "\\1") : raw
        end
      end

      def normalized_lines(body)
        body.to_s.delete_prefix("\uFEFF").lines(chomp: true).map(&:strip).reject(&:empty?)
      end

      def integer_tag(lines, prefix, default: nil)
        value = lines.find { |line| line.start_with?(prefix) }
        value ? Integer(value.delete_prefix(prefix)) : default
      end

      def decimal_tag(lines, prefix)
        value = lines.find { |line| line.start_with?(prefix) }
        value && Float(value.delete_prefix(prefix))
      end

      def parse_byte_range(value, implicit_offset:)
        length, offset = value.split("@", 2)
        if offset.blank? && implicit_offset.nil?
          raise ParseError, "implicit byte range has no preceding range"
        end
        { "length" => Integer(length), "offset" => offset ? Integer(offset) : implicit_offset }
      end

      def absolute_url(base, relative)
        relative.present? ? URI.join(base, relative).to_s : nil
      end

      def yes?(value)
        value.to_s.casecmp?("YES")
      end
    end
  end
end
