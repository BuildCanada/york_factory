require "digest"
require "json"

module Warehouse
  module Broadcasts
    class ClipExporter
      class CoverageError < ArgumentError; end

      COVERAGE_TOLERANCE = 0.1.seconds
      MAX_PARTS = 100
      MAX_DURATION = 30.minutes
      STALE_PROCESSING_AFTER = 70.minutes

      def initialize(clip, storage: nil, command: nil, ffmpeg: "ffmpeg", ffprobe: "ffprobe")
        @clip = clip
        @storage = storage || Storage.new
        @command = command || Command.new(timeout: 10.minutes)
        @exact_command = command
        @ffmpeg = ffmpeg
        @ffprobe = ffprobe
      end

      def call
        return clip unless claim!
        validate_request!

        Dir.mktmpdir("broadcast-clip-") do |directory|
          parts = playback_parts
          validate_coverage!(parts, clip.starts_at, clip.ends_at, "media")
          source_path = assemble_parts(parts, directory)
          source_timing = probe_media(source_path)
          output_path = File.join(directory, "clip.mp4")
          if clip.export_mode == "exact"
            start_offset = clip.starts_at - parts.first.starts_at
            export_exact_mp4(source_path, output_path, start_offset, clip.ends_at - clip.starts_at)
          else
            start_offset, target_end_offset = copy_boundaries(source_path, parts.first.starts_at, source_timing)
            export_copy_mp4(source_path, output_path, start_offset, target_end_offset)
          end
          output_timing = probe_media(output_path)

          actual_starts_at = clip.export_mode == "exact" ? clip.starts_at : parts.first.starts_at + start_offset
          actual_ends_at = actual_starts_at + output_timing.fetch(:duration)
          validate_export!(actual_starts_at, actual_ends_at, output_timing, mode: clip.export_mode)
          caption_paths = export_captions(directory, actual_starts_at, actual_ends_at)
          attach_outputs!(output_path, caption_paths, actual_starts_at, actual_ends_at, parts, output_timing)
        end
        clip
      rescue => error
        clip.update_columns(state: "failed", error: error.message.truncate(2_000), updated_at: Time.current) if clip.persisted?
        raise
      end

      private

      attr_reader :clip, :storage, :command

      def claim!
        claimed = false
        clip.with_lock do
          return false if clip.state == "ready" && clip.file.attached?
          return false if clip.state == "processing" && clip.updated_at > STALE_PROCESSING_AFTER.ago
          clip.update!(state: "processing", error: nil)
          claimed = true
        end
        claimed
      end

      def stream
        clip.media_recording.media_stream
      end

      def validate_request!
        recording = clip.media_recording
        raise ArgumentError, "clip begins before its recording" if clip.starts_at < recording.starts_at
        raise ArgumentError, "clip extends past its recording" if recording.ends_at && clip.ends_at > recording.ends_at
        raise ArgumentError, "clip duration exceeds #{MAX_DURATION.inspect}" if clip.ends_at - clip.starts_at > MAX_DURATION
      end

      def playback_parts
        audio_id = clip.media_track_id&.to_s
        stream.objects.current_playback
          .where("metadata ->> 'audio_track_id' IS NOT DISTINCT FROM ?", audio_id)
          .where("starts_at < ? AND ends_at > ?", clip.ends_at, clip.starts_at)
          .order(:starts_at, :id).limit(MAX_PARTS + 1).to_a.tap do |parts|
            raise ArgumentError, "clip requires more than #{MAX_PARTS} playback parts" if parts.length > MAX_PARTS
          end
      end

      def validate_coverage!(objects, starts_at, ends_at, label)
        raise CoverageError, "missing #{label} coverage at clip start" if objects.empty? || objects.first.starts_at > starts_at + COVERAGE_TOLERANCE

        cursor = starts_at
        previous = nil
        objects.each do |object|
          if previous && object.starts_at < previous.ends_at - COVERAGE_TOLERANCE
            raise CoverageError, "overlapping #{label} coverage near #{object.starts_at.iso8601}"
          end
          raise CoverageError, "missing #{label} coverage near #{cursor.iso8601}" if object.starts_at > cursor + COVERAGE_TOLERANCE
          cursor = [ cursor, object.ends_at ].max
          previous = object
        end
        raise CoverageError, "missing #{label} coverage at clip end" if cursor < ends_at - COVERAGE_TOLERANCE
      end

      def assemble_parts(parts, directory)
        files = parts.to_h do |part|
          path = File.join(directory, "part-#{part.id}.ts")
          storage.download_to(key: part.object_key, path:)
          [ part.id, path ]
        end
        list = write_concat_list(parts, files, directory, "parts")
        output = File.join(directory, "assembled.ts")
        command.run(
          @ffmpeg, "-nostdin", "-hide_banner", "-loglevel", "error",
          "-f", "concat", "-safe", "0", "-i", list,
          "-copyts", "-start_at_zero", "-c", "copy", "-mpegts_flags", "+resend_headers",
          "-muxdelay", "0", "-y", output
        )
        output
      end

      def exact_command(requested_duration)
        @exact_command ||= Command.new(timeout: requested_duration * 2 + 2.minutes)
      end

      def copy_boundaries(path, timeline_start, source_timing)
        requested_start = clip.starts_at - timeline_start
        requested_end = clip.ends_at - timeline_start
        keyframes = video_keyframes(path, source_timing.fetch(:start))
        if keyframes.any?
          actual_start = keyframes.select { |timestamp| timestamp <= requested_start + COVERAGE_TOLERANCE }.last || keyframes.first
          target_end = keyframes.find { |timestamp| timestamp >= requested_end - COVERAGE_TOLERANCE } || source_timing.fetch(:duration)
        else
          # Audio-only packet copy has no video keyframe constraint. FFmpeg will
          # select the nearest independently decodable audio packet.
          actual_start = [ requested_start, 0 ].max
          target_end = [ requested_end, source_timing.fetch(:duration) ].min
        end
        raise ArgumentError, "no decodable copy interval covers the request" unless target_end > actual_start

        [ actual_start, target_end ]
      end

      def video_keyframes(path, source_start)
        result = command.run(
          @ffprobe, "-v", "error", "-select_streams", "v:0", "-skip_frame", "nokey",
          "-show_frames", "-show_entries", "frame=best_effort_timestamp_time", "-of", "json", path
        )
        JSON.parse(result.stdout).fetch("frames", []).filter_map do |frame|
          Float(frame["best_effort_timestamp_time"]) - source_start if frame["best_effort_timestamp_time"]
        end.sort
      rescue JSON::ParserError
        raise ArgumentError, "ffprobe could not determine clip keyframes"
      end

      def export_copy_mp4(source_path, output_path, actual_start, target_end)
        command.run(
          @ffmpeg, "-nostdin", "-hide_banner", "-loglevel", "error",
          "-ss", format("%.6f", actual_start), "-i", source_path,
          "-t", format("%.6f", target_end - actual_start),
          "-map", "0:v:0?", "-map", "0:a:0?", "-c", "copy",
          "-avoid_negative_ts", "make_zero", "-movflags", "+faststart", "-y", output_path
        )
      end

      def export_exact_mp4(source_path, output_path, requested_start, requested_duration)
        exact_command(requested_duration).run(
          @ffmpeg, "-nostdin", "-hide_banner", "-loglevel", "error",
          "-ss", format("%.6f", requested_start), "-i", source_path,
          "-t", format("%.6f", requested_duration),
          "-map", "0:v:0?", "-map", "0:a:0?", "-sn", "-dn",
          "-c:v", "libx264", "-preset", "veryfast", "-crf", "18", "-pix_fmt", "yuv420p",
          "-c:a", "aac", "-b:a", "192k",
          "-threads", "2", "-movflags", "+faststart", "-y", output_path
        )
      end

      def probe_media(path)
        result = command.run(
          @ffprobe, "-v", "error",
          "-show_entries", "format=start_time,duration:stream=codec_type,start_time,avg_frame_rate,sample_rate",
          "-of", "json", path
        )
        probe = JSON.parse(result.stdout)
        duration = Float(probe.dig("format", "duration"))
        start = Float(probe.dig("format", "start_time") || 0)
        types = probe.fetch("streams").map { |item| item.fetch("codec_type") }
        raise ArgumentError, "export has no media stream" if (types & %w[video audio]).empty?
        raise ArgumentError, "export duration is empty" unless duration.positive?

        { start:, duration:, stream_types: types, probe: }
      rescue JSON::ParserError, KeyError, TypeError
        raise ArgumentError, "ffprobe did not return usable clip timing"
      end

      def validate_export!(actual_starts_at, actual_ends_at, timing, mode:)
        recording = clip.media_recording
        boundary_label = mode == "exact" ? "precise export" : "nearest copy keyframe"
        raise ArgumentError, "#{boundary_label} begins outside this recording" if actual_starts_at < recording.starts_at
        if recording.ends_at && actual_ends_at > recording.ends_at + COVERAGE_TOLERANCE
          raise ArgumentError, "#{boundary_label} ends outside this recording"
        end
        if mode == "exact"
          requested_duration = clip.ends_at - clip.starts_at
          tolerance = exact_duration_tolerance(timing)
          stream_starts = timing.fetch(:probe).fetch("streams").filter_map do |stream|
            Float(stream["start_time"]) if stream["codec_type"].in?(%w[video audio]) && stream["start_time"]
          end
          if timing.fetch(:start).abs > tolerance ||
              (stream_starts.any? && stream_starts.max - stream_starts.min > tolerance)
            raise ArgumentError,
              "precise export timestamps are not synchronized " \
              "(container #{timing.fetch(:start).round(6)}s, streams #{stream_starts.map { |value| value.round(6) }.inspect})"
          end
          if (timing.fetch(:duration) - requested_duration).abs > tolerance
            raise ArgumentError,
              "precise export duration #{timing.fetch(:duration).round(6)}s differs from " \
              "the #{requested_duration.round(6)}s selection by more than one frame"
          end
          return
        end

        raise ArgumentError, "export starts after the requested interval" if actual_starts_at > clip.starts_at + COVERAGE_TOLERANCE
        raise ArgumentError, "export ends before the requested interval" if actual_ends_at < clip.ends_at - COVERAGE_TOLERANCE
        raise ArgumentError, "export timing is implausibly long" if timing.fetch(:duration) > (clip.ends_at - clip.starts_at) + 30.seconds
      end

      def exact_duration_tolerance(timing)
        video = timing.fetch(:probe).fetch("streams").find { |stream| stream["codec_type"] == "video" }
        if video
          rate = Rational(video["avg_frame_rate"])
          return (1.0 / rate) + 0.005 if rate.positive?
        end

        audio = timing.fetch(:probe).fetch("streams").find { |stream| stream["codec_type"] == "audio" }
        sample_rate = Integer(audio["sample_rate"], exception: false) if audio
        return (1024.0 / sample_rate) + 0.005 if sample_rate&.positive?

        COVERAGE_TOLERANCE
      rescue ArgumentError, TypeError, ZeroDivisionError
        COVERAGE_TOLERANCE
      end

      def export_captions(directory, actual_starts_at, actual_ends_at)
        requested_caption_objects(actual_starts_at, actual_ends_at).to_h do |track, objects|
          cues = objects.flat_map do |object|
            WebVtt.parse(storage.download(key: object.object_key)).filter_map do |cue|
              absolute_start = object.starts_at + cue.start_seconds
              absolute_end = object.starts_at + cue.end_seconds
              start_seconds = [ absolute_start, actual_starts_at ].max - actual_starts_at
              end_seconds = [ absolute_end, actual_ends_at ].min - actual_starts_at
              next unless end_seconds > start_seconds

              cue.with(start_seconds:, end_seconds:)
            end
          end
          path = File.join(directory, "captions-#{track.language}.vtt")
          File.binwrite(path, WebVtt.render(cues.sort_by(&:start_seconds)))
          [ track, path ]
        end
      end

      def requested_caption_objects(starts_at, ends_at)
        available = stream.tracks.where(kind: "captions", language: %w[en fr]).order(:language, :id).to_a
        metadata = clip.metadata.to_h
        languages = metadata.key?("caption_languages") ? Array(metadata["caption_languages"]) : available.map(&:language)
        languages.uniq.to_h do |language|
          candidates = available.select { |track| track.language == language }
          raise ArgumentError, "#{language} captions are unavailable" if candidates.empty?

          selection = candidates.lazy.filter_map do |track|
            objects = track.media_objects.where(kind: "caption_file")
              .where("starts_at < ? AND ends_at > ?", ends_at, starts_at).order(:starts_at, :id).to_a
            begin
              validate_coverage!(objects, starts_at, ends_at, "#{language} captions")
              [ track, objects ]
            rescue CoverageError
              # A prior carrier can have stale or incomplete caption coverage.
              # Only select a track covering the entire actual export interval.
              nil
            end
          end.first
          selection || raise(CoverageError, "missing #{language} captions coverage for the exported interval")
        end
      end

      def attach_outputs!(output_path, caption_paths, actual_starts_at, actual_ends_at, parts, timing)
        File.open(output_path, "rb") do |io|
          clip.file.attach(io:, filename: "clip-#{clip.id}.mp4", content_type: "video/mp4")
        end
        caption_paths.each do |track, path|
          File.open(path, "rb") do |io|
            clip.captions.attach(
              io:,
              filename: "clip-#{clip.id}-#{track.language}.vtt",
              content_type: "text/vtt"
            )
          end
        end
        clip.update!(
          state: "ready",
          actual_starts_at:,
          actual_ends_at:,
          error: nil,
          metadata: clip.metadata.to_h.merge(
            "source_object_ids" => parts.map(&:id),
            "recipe" => clip.export_mode == "exact" ? "exact-h264-aac-v1" : "fast-copy-v1",
            "duration" => timing.fetch(:duration),
            "caption_languages" => caption_paths.keys.map(&:language)
          )
        )
      end

      def write_concat_list(objects, files, directory, name)
        path = File.join(directory, "#{name}.ffconcat")
        File.write(path, ([ "ffconcat version 1.0" ] + objects.map { |object| "file '#{files.fetch(object.id)}'" }).join("\n") + "\n")
        path
      end
    end
  end
end
