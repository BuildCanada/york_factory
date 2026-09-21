module Warehouse::Broadcasts
  # A bounded snapshot keeps player time stable while new parts arrive. Gaps
  # occupy time in the presentation; seeking never silently skips lost footage.
  class Playback
    # Include the two-minute lead-in plus a full 30-minute clip preview.
    WINDOW = 32.minutes
    attr_reader :recording, :audio_track, :parts, :starts_at, :ends_at

    def initialize(recording, audio_track: nil, at: nil, storage: nil)
      @recording, @audio_track, @storage = recording, audio_track, storage
      requested = at || recording.starts_at
      requested = [ requested, recording.starts_at ].max
      @window_start = [ requested - 2.minutes, recording.starts_at ].max
      scope = recording.stream.objects.current_playback
        .where("starts_at < ? AND ends_at > ?", @window_start + WINDOW, @window_start)
        .where("metadata ->> 'audio_track_id' IS NOT DISTINCT FROM ?", audio_track&.id&.to_s)
      scope = scope.where("starts_at < ?", recording.ends_at) if recording.ends_at
      @parts = scope.order(:starts_at, :id).limit(100).to_a
      @starts_at = [ parts.first&.starts_at || @window_start, @window_start ].min
      @ends_at = if recording.ends_at && recording.state != "open"
        [ recording.ends_at, @window_start + WINDOW ].min
      else
        parts.last&.ends_at || @starts_at
      end
    end

    def playlist(gap_url:)
      return nil if parts.empty?

      durations = parts.map { |part| part.ends_at - part.starts_at }
      gap_durations = gaps.map { |from, to| to - from }
      lines = [ "#EXTM3U", "#EXT-X-VERSION:6",
        "#EXT-X-TARGETDURATION:#{(durations + gap_durations).max.ceil}",
        "#EXT-X-MEDIA-SEQUENCE:0", "#EXT-X-PLAYLIST-TYPE:VOD" ]
      cursor = starts_at
      parts.each_with_index do |part, index|
        gap = part.starts_at - cursor
        if gap > 0.05
          lines.concat([ "#EXT-X-GAP", "#EXTINF:#{format('%.6f', gap)},", gap_url ])
        elsif gap < -0.05
          raise ArgumentError, "Overlapping playback parts require reprocessing"
        end
        lines << "#EXT-X-DISCONTINUITY" if cursor > starts_at || gap > 0.05
        lines << "#EXT-X-PROGRAM-DATE-TIME:#{part.starts_at.utc.iso8601(6)}"
        next_part = parts[index + 1]
        # AAC packet rounding can overlap adjacent parts by a few milliseconds.
        # Pin the presentation slot to its next UTC anchor instead of accumulating
        # that rounding into transcript/seek drift over a long recording.
        finish = if next_part && (next_part.starts_at - part.ends_at).abs <= 0.05
          next_part.starts_at
        else
          part.ends_at
        end
        lines << "#EXTINF:#{format('%.6f', finish - part.starts_at)},"
        lines << storage.url(key: part.object_key, expires_in: 3600)
        cursor = finish
      end
      tail = ends_at - cursor
      lines.concat([ "#EXT-X-GAP", "#EXTINF:#{format('%.6f', tail)},", gap_url ]) if tail > 0.05
      (lines << "#EXT-X-ENDLIST").join("\n") + "\n"
    end

    def gaps
      result = parts.each_cons(2).filter_map do |left, right|
        [ left.ends_at, right.starts_at ] if right.starts_at - left.ends_at > 0.05
      end
      result.unshift([ starts_at, parts.first.starts_at ]) if parts.first && parts.first.starts_at - starts_at > 0.05
      result << [ parts.last.ends_at, ends_at ] if parts.last && ends_at - parts.last.ends_at > 0.05
      result
    end

    private

    def storage
      @storage ||= Storage.new
    end
  end
end
