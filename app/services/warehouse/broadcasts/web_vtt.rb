module Warehouse
  module Broadcasts
    module WebVtt
      Cue = Data.define(:start_seconds, :end_seconds, :text, :settings, :identifier)
      Passage = Data.define(:start_seconds, :end_seconds, :text)

      TIMING_LINE = /\A(?<start>\d{2}:\d{2}:\d{2}\.\d{3}|\d{2}:\d{2}\.\d{3})\s+-->\s+(?<finish>\d{2}:\d{2}:\d{2}\.\d{3}|\d{2}:\d{2}\.\d{3})(?:\s+(?<settings>.*))?\z/

      module_function

      def parse(source)
        # Storage downloads and File.binread return ASCII-8BIT strings. WebVTT
        # is UTF-8, so transcoding that binary label would replace every byte
        # of a multibyte French character. Apply the specified encoding first,
        # then replace only genuinely invalid byte sequences.
        normalized = source.to_s.dup.force_encoding(Encoding::UTF_8).scrub.sub(/\A\uFEFF/, "")
        lines = normalized.gsub("\r\n", "\n").gsub("\r", "\n").lines(chomp: true)
        raise ArgumentError, "not a WebVTT document" unless lines.first.to_s.start_with?("WEBVTT")

        cues = []
        index = 1
        while index < lines.length
          index += 1 while index < lines.length && lines[index].empty?
          break if index >= lines.length

          if metadata_block?(lines[index])
            index += 1
            index += 1 while index < lines.length && !lines[index].empty?
            next
          end

          identifier = nil
          unless TIMING_LINE.match?(lines[index])
            if index + 1 < lines.length && TIMING_LINE.match?(lines[index + 1])
              identifier = lines[index]
              index += 1
            else
              index += 1
              next
            end
          end

          match = TIMING_LINE.match(lines[index])
          start_seconds = parse_timestamp(match[:start])
          end_seconds = parse_timestamp(match[:finish])
          index += 1

          text_lines = []
          while index < lines.length
            break if TIMING_LINE.match?(lines[index])

            if lines[index].empty?
              following = index
              following += 1 while following < lines.length && lines[following].empty?
              break if following >= lines.length || cue_starts_at?(lines, following) || metadata_block?(lines[following])

              # FFmpeg's 608 decoder sometimes emits a blank display row
              # immediately after the timing line. It is not a cue delimiter
              # when ordinary caption text follows it.
              index = following
              next
            end

            text_lines << lines[index]
            index += 1
          end

          if end_seconds > start_seconds
            cues << Cue.new(
              start_seconds:,
              end_seconds:,
              text: text_lines.join("\n"),
              settings: match[:settings].to_s,
              identifier:
            )
          end
        end
        cues
      end

      def render(cues)
        body = Array(cues).map do |cue|
          timing = "#{format_timestamp(cue.start_seconds)} --> #{format_timestamp(cue.end_seconds)}"
          timing = "#{timing} #{cue.settings}" if cue.settings.present?
          [ cue.identifier.presence, timing, cue.text.to_s ].compact.join("\n")
        end.join("\n\n")
        "WEBVTT\n\n#{body}#{body.present? ? "\n" : ""}"
      end

      # Intersects cues with [from, to), clamps them to the interval, and by
      # default rebases the interval start to 00:00.000.
      def clip(source_or_cues, from:, to:, rebase: true)
        raise ArgumentError, "clip end must be after start" unless to > from

        cues = source_or_cues.is_a?(String) ? parse(source_or_cues) : Array(source_or_cues)
        shift = rebase ? from : 0
        cues.filter_map do |cue|
          start_seconds = [ cue.start_seconds, from ].max
          end_seconds = [ cue.end_seconds, to ].min
          next unless end_seconds > start_seconds

          cue.with(start_seconds: start_seconds - shift, end_seconds: end_seconds - shift)
        end
      end

      # Turns display-oriented roll-up captions into deterministic search text.
      # Only lines appended to the previous roll-up state are added, preserving
      # genuine later repetitions after the display state has changed.
      def passages(source_or_cues, duration:, window_seconds: 30)
        cues = source_or_cues.is_a?(String) ? parse(source_or_cues) : Array(source_or_cues)
        windows = Hash.new { |hash, key| hash[key] = [] }
        previous_lines = []

        cues.each do |cue|
          lines = caption_lines(cue.text)
          overlap = suffix_prefix_overlap(previous_lines, lines)
          novel_lines = lines.drop(overlap)
          windows[(cue.start_seconds / window_seconds).floor].concat(novel_lines)
          previous_lines = lines
        end

        windows.keys.sort.filter_map do |index|
          start_seconds = index * window_seconds
          end_seconds = [ start_seconds + window_seconds, duration ].min
          text = windows.fetch(index).join(" ").squish
          next if text.blank? || end_seconds <= start_seconds

          Passage.new(start_seconds:, end_seconds:, text:)
        end
      end

      def parse_timestamp(timestamp)
        parts = timestamp.split(":")
        seconds = parts.pop.to_f
        minutes = parts.pop.to_i
        hours = parts.pop.to_i
        (hours * 3600) + (minutes * 60) + seconds
      end

      def format_timestamp(seconds)
        milliseconds = (seconds.to_f * 1000).round
        hours, remainder = milliseconds.divmod(3_600_000)
        minutes, remainder = remainder.divmod(60_000)
        secs, millis = remainder.divmod(1000)
        format("%02d:%02d:%02d.%03d", hours, minutes, secs, millis)
      end

      def metadata_block?(line)
        line.to_s.match?(/\A(?:NOTE|STYLE|REGION)(?:\s|\z)/)
      end
      private_class_method :metadata_block?

      def cue_starts_at?(lines, index)
        TIMING_LINE.match?(lines[index]) ||
          (index + 1 < lines.length && TIMING_LINE.match?(lines[index + 1]))
      end
      private_class_method :cue_starts_at?

      def caption_lines(text)
        text.to_s.lines.map { |line| line.gsub("\\h", " ").strip }.reject(&:blank?)
      end
      private_class_method :caption_lines

      def suffix_prefix_overlap(previous, current)
        [ previous.length, current.length ].min.downto(1).find do |length|
          previous.last(length) == current.first(length)
        end || 0
      end
      private_class_method :suffix_prefix_overlap
    end
  end
end
