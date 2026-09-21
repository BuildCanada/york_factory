module Admin::BroadcastsHelper
  def broadcast_transcript(passage)
    safe_join(Warehouse::Broadcasts::TranscriptSearch.segments(passage).map do |segment|
      segment[:match] ? content_tag(:mark, segment[:text], class: "broadcast-match") : ERB::Util.html_escape(segment[:text])
    end)
  end

  def broadcast_title(record)
    record.title_en.presence || record.title_fr.presence || "Untitled broadcast"
  end

  def broadcast_offset(time, recording)
    [ (time - recording.starts_at).round(3), 0 ].max
  end

  def broadcast_time(time)
    time&.utc&.strftime("%Y-%m-%d %H:%M:%S UTC") || "—"
  end

  def broadcast_duration(seconds)
    seconds = seconds.to_i
    format("%02d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
  end

  def broadcast_timecode(seconds)
    milliseconds = [ (seconds.to_f * 1000).round, 0 ].max
    format("%02d:%02d:%02d.%03d", milliseconds / 3_600_000,
      milliseconds / 60_000 % 60, milliseconds / 1000 % 60, milliseconds % 1000)
  end
end
