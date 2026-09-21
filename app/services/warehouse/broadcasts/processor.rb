require "digest"
require "fileutils"
require "json"
require "tempfile"

module Warehouse
  module Broadcasts
    class Processor
      class InvalidOutput < StandardError; end

      Window = Data.define(:starts_at, :ends_at, :carrier_objects) do
        def duration
          ends_at - starts_at
        end
      end

      RECIPE = "cpac-playback-v2"
      CAPTION_RECIPE = "cpac-a53-webvtt-v2"
      TARGET_DURATION = 60.seconds
      REPLAY_DURATION = 18.seconds
      GAP_TOLERANCE = 0.25.seconds
      MAX_WINDOWS = 4

      def initialize(stream, storage: nil, command: nil, ffmpeg: "ffmpeg", ffprobe: "ffprobe",
        target_duration: TARGET_DURATION, replay_duration: REPLAY_DURATION, max_windows: MAX_WINDOWS)
        @stream = stream
        @storage = storage || Storage.new
        @command = command || Command.new
        @ffmpeg = ffmpeg
        @ffprobe = ffprobe
        @target_duration = target_duration.to_f
        @replay_duration = replay_duration.to_f
        @max_windows = max_windows
      end

      def call
        processed = 0
        remaining_windows = @max_windows
        @more_work = false

        carrier_tracks.each do |carrier|
          pending = complete_windows(source_objects_for(carrier)).select { |window| window_pending?(window, carrier) }
          windows = pending.first(remaining_windows)
          @more_work ||= pending.length > windows.length
          remaining_windows -= windows.length

          windows.each do |window|
            Dir.mktmpdir("broadcast-process-") do |directory|
              local_files = download_objects(window.carrier_objects, directory)
              processed += process_playback(window, carrier, local_files, directory)
              processed += process_captions(window, carrier, local_files, directory) if carrier.kind == "video"
            end
          end
        end
        mark_processed if processed.positive?
        processed
      end

      def more_work?
        @more_work == true
      end

      private

      attr_reader :stream, :storage, :command

      def carrier_tracks
        videos = stream.tracks.where(kind: "video").order(last_seen_at: :desc, id: :desc).select do |track|
          source_objects_for(track).exists?
        end
        videos.presence || audio_tracks
      end

      def audio_tracks
        @audio_tracks ||= stream.tracks.where(kind: "audio").order(last_seen_at: :desc, id: :desc).select do |track|
          source_objects_for(track).exists?
        end
      end

      def caption_tracks(carrier)
        stream.tracks.where(kind: "captions", parent_track_id: carrier.id).order(:id)
      end

      def source_objects_for(track)
        track.media_objects.where(kind: "source_segment").where.not(starts_at: nil, ends_at: nil).order(:starts_at, :sequence, :id)
      end

      def complete_windows(objects)
        result = []
        current = []
        objects.each do |object|
          if current.any? && boundary_between?(current.last, object)
            result << build_window(current)
            current = []
          end
          current << object
          if current.last.ends_at - current.first.starts_at >= @target_duration
            result << build_window(current)
            current = []
          end
        end
        result << build_window(current) if current.any? && finalized_through?(current.last.ends_at)
        result
      end

      def build_window(objects)
        Window.new(starts_at: objects.first.starts_at, ends_at: objects.last.ends_at, carrier_objects: objects.freeze)
      end

      def boundary_between?(previous, following)
        following.starts_at > previous.ends_at + GAP_TOLERANCE ||
          following.epoch != previous.epoch || following.metadata["discontinuity"] || following.metadata["gap_before"]
      end

      def finalized_through?(time)
        stream.recordings.where(state: %w[finalized partial])
          .where("ends_at IS NOT NULL AND ends_at >= ?", time - GAP_TOLERANCE).exists?
      end

      def window_pending?(window, carrier)
        playback_pending = if carrier.kind == "video"
          (audio_tracks.presence || [ nil ]).any? do |audio_track|
            audio_objects = audio_track && covering_objects(source_objects_for(audio_track), window.starts_at, window.ends_at)
            next false if audio_track && audio_objects.nil?
            objects = (window.carrier_objects + Array(audio_objects)).uniq
            !stream.objects.exists?(identity_key: playback_identity(objects, audio_track))
          end
        else
          !stream.objects.exists?(identity_key: playback_identity(window.carrier_objects, carrier))
        end
        return true if playback_pending

        caption_tracks(carrier).any? do |track|
          replay = caption_replay_objects(carrier, window)
          identity = caption_identity((replay + window.carrier_objects).uniq, track, window)
          object = stream.objects.find_by(identity_key: identity)
          object.nil? || (!object.metadata["empty"] &&
            !track.media_transcript_passages.where("metadata ->> 'caption_object_id' = ?", object.id.to_s).exists?)
        end
      end

      def process_playback(window, carrier, carrier_files, directory)
        selections = if carrier.kind == "video"
          audio_tracks.presence || [ nil ]
        else
          [ carrier ]
        end

        selections.count do |audio_track|
          audio_objects = if carrier.kind == "video" && audio_track
            covering_objects(source_objects_for(audio_track), window.starts_at, window.ends_at)
          elsif carrier.kind == "audio"
            window.carrier_objects
          else
            []
          end
          next false if audio_track && audio_objects.nil?

          source_objects = (window.carrier_objects + Array(audio_objects)).uniq
          identity = playback_identity(source_objects, audio_track)
          next false if stream.objects.exists?(identity_key: identity)

          files = carrier_files.merge(download_objects(Array(audio_objects) - window.carrier_objects, directory))
          output_path = File.join(directory, "playback-#{audio_track&.id || 'silent'}.ts")
          remux_playback(window, carrier, window.carrier_objects, audio_objects, files, directory, output_path)
          timing = probe_media(output_path)
          starts_at = window.starts_at + timing.fetch(:start)
          ends_at = window.starts_at + timing.fetch(:finish)
          validate_output_timing!(window, starts_at, ends_at)

          checksum = Digest::SHA256.file(output_path).hexdigest
          identity_digest = identity.delete_prefix("playback:")
          object_key = "broadcasts/#{stream.id}/playback/#{identity_digest}-#{checksum}.ts"
          upload_file(object_key, output_path, "video/mp2t")
          persist_playback_object!(window:, audio_track:, attributes: {
            media_track: carrier,
            kind: "playback_part",
            identity_key: identity,
            object_key:,
            checksum:,
            byte_size: File.size(output_path),
            content_type: "video/mp2t",
            starts_at:,
            ends_at:,
            epoch: source_objects.map(&:epoch).compact.max || 0,
            sequence: window.carrier_objects.first.sequence,
            metadata: {
              "recipe" => RECIPE,
              "source_object_ids" => source_objects.map(&:id),
              "carrier_source_object_ids" => window.carrier_objects.map(&:id),
              "audio_track_id" => audio_track&.id&.to_s,
              "requested_starts_at" => window.starts_at.iso8601(6),
              "requested_ends_at" => window.ends_at.iso8601(6),
              "duration" => ends_at - starts_at,
              "ffprobe" => timing.fetch(:probe)
            }
          })
          true
        end
      end

      def process_captions(window, carrier, carrier_files, directory)
        caption_tracks(carrier).count do |track|
          field = Integer(track.metadata.fetch("caption_field"))
          next false unless stream.provider == "cpac" && [ 1, 2 ].include?(field)

          replay_objects = caption_replay_objects(carrier, window)
          extraction_objects = (replay_objects + window.carrier_objects).uniq
          identity = caption_identity(extraction_objects, track, window)
          if (existing = stream.objects.find_by(identity_key: identity))
            cues = WebVtt.parse(storage.download(key: existing.object_key))
            replace_passages!(track, existing, cues, existing.ends_at - existing.starts_at)
            next false
          end

          files = carrier_files.merge(download_objects(replay_objects - window.carrier_objects, directory))
          input_path = File.join(directory, "captions-#{track.id}.ts")
          concatenate_bytes(extraction_objects.map { |object| files.fetch(object.id) }, input_path)
          raw_path = File.join(directory, "captions-#{track.id}-raw.vtt")
          extract_captions(input_path, raw_path, field)

          extraction_start = extraction_objects.first.starts_at
          from = window.starts_at - extraction_start
          to = window.ends_at - extraction_start
          raw = File.exist?(raw_path) ? File.binread(raw_path) : "WEBVTT\n\n"
          cues = WebVtt.clip(raw, from:, to:)
          vtt = WebVtt.render(cues)
          checksum = Digest::SHA256.hexdigest(vtt)
          identity_digest = identity.delete_prefix("caption:")
          object_key = "broadcasts/#{stream.id}/captions/#{track.language}/#{identity_digest}-#{checksum}.vtt"
          storage.upload(key: object_key, body: vtt, content_type: "text/vtt")
          object = create_media_object!(
            media_track: track,
            kind: "caption_file",
            identity_key: identity,
            object_key:,
            checksum:,
            byte_size: vtt.bytesize,
            content_type: "text/vtt",
            starts_at: window.starts_at,
            ends_at: window.ends_at,
            epoch: window.carrier_objects.map(&:epoch).compact.max || 0,
            sequence: window.carrier_objects.first.sequence,
            metadata: {
              "recipe" => CAPTION_RECIPE,
              "source_object_ids" => extraction_objects.map(&:id),
              "window_source_object_ids" => window.carrier_objects.map(&:id),
              "caption_field" => field,
              "language" => track.language,
              "timestamps" => "local_to_object_starts_at",
              "replay_seconds" => from,
              "cue_count" => cues.length,
              "empty" => cues.empty?
            }
          )
          replace_passages!(track, object, cues, window.duration)
          true
        end
      end

      def covering_objects(scope, starts_at, ends_at)
        objects = scope.where("starts_at < ? AND ends_at > ?", ends_at, starts_at).to_a
        # CPAC's audio segments start about one AAC frame after the matching
        # video segments. That makes the preceding audio segment overlap a
        # video window by one frame even though the next audio segment is the
        # correct source for that window. FFmpeg's concat demuxer does not
        # reliably seek raw ADTS input, so keeping that redundant object can
        # copy an entire stale 4.8/6.4-second segment with reset timestamps.
        while objects.length > 1 && objects.second.starts_at <= starts_at + GAP_TOLERANCE
          objects.shift
        end
        return if objects.empty? || objects.first.starts_at > starts_at + GAP_TOLERANCE

        cursor = starts_at
        previous = nil
        objects.each do |object|
          return if previous && boundary_between?(previous, object)
          return if object.starts_at > cursor + GAP_TOLERANCE
          cursor = [ cursor, object.ends_at ].max
          previous = object
          break if cursor >= ends_at - GAP_TOLERANCE
        end
        return if cursor < ends_at - GAP_TOLERANCE

        objects
      end

      def caption_replay_objects(carrier, window)
        source_objects_for(carrier)
          .where("ends_at <= ? AND ends_at > ?", window.starts_at, window.starts_at - @replay_duration)
          .to_a
      end

      def download_objects(objects, directory)
        objects.to_h do |object|
          extension = File.extname(object.object_key).presence || ".bin"
          path = File.join(directory, "source-#{object.id}#{extension}")
          storage.download_to(key: object.object_key, path:)
          [ object.id, path ]
        end
      end

      def remux_playback(window, carrier, carrier_objects, audio_objects, files, directory, output_path)
        arguments = [ @ffmpeg, "-nostdin", "-hide_banner", "-loglevel", "error" ]
        carrier_list = write_concat_list(carrier_objects, files, directory, "carrier")
        arguments.concat([ "-f", "concat", "-safe", "0", "-i", carrier_list ])
        if carrier.kind == "video" && audio_objects.present?
          audio_list = write_concat_list(audio_objects, files, directory, "audio")
          audio_trim = [ window.starts_at - audio_objects.first.starts_at, 0 ].max
          audio_input = audio_list
          if audio_trim.positive?
            # Input-side seeking is ignored by FFmpeg's concat demuxer for raw
            # ADTS in practice. Trim as an output step first so stale packets
            # cannot be copied with freshly reset timestamps.
            audio_input = File.join(directory, "audio-trimmed.ts")
            command.run(
              @ffmpeg, "-nostdin", "-hide_banner", "-loglevel", "error",
              "-f", "concat", "-safe", "0", "-i", audio_list,
              "-ss", format("%.6f", audio_trim), "-t", format("%.6f", window.duration),
              "-map", "0:a:0", "-c", "copy", "-f", "mpegts", "-muxdelay", "0", "-muxpreload", "0",
              "-y", audio_input
            )
          end
          audio_offset = audio_trim.positive? ? 0 : [ audio_objects.first.starts_at - window.starts_at, 0 ].max
          arguments.concat([ "-itsoffset", format("%.6f", audio_offset) ])
          if audio_trim.positive?
            arguments.concat([ "-i", audio_input ])
          else
            arguments.concat([ "-f", "concat", "-safe", "0", "-i", audio_input ])
          end
          arguments.concat([ "-map", "0:v:0", "-map", "1:a:0" ])
        elsif carrier.kind == "video"
          arguments.concat([ "-map", "0:v:0" ])
        else
          arguments.concat([ "-map", "0:a:0" ])
        end
        arguments.concat([
          "-t", format("%.6f", window.duration), "-c", "copy", "-mpegts_flags", "+resend_headers",
          "-muxdelay", "0", "-muxpreload", "0", "-avoid_negative_ts", "make_zero", "-y", output_path
        ])
        command.run(*arguments)
      end

      def extract_captions(input_path, output_path, field)
        data_field = field == 1 ? "first" : "second"
        movie_path = input_path.gsub("\\", "\\\\").gsub(":", "\\:").gsub("'", "\\'")
        command.run(
          @ffmpeg, "-nostdin", "-hide_banner", "-loglevel", "error",
          "-data_field", data_field, "-f", "lavfi", "-i", "movie='#{movie_path}'[out0+subcc]",
          "-map", "0:s:0", "-c:s", "webvtt", "-y", output_path
        )
      rescue Command::Failed => error
        # A carrier with no caption packets is a valid, explicit empty result.
        raise unless error.result&.stderr.to_s.match?(/does not contain any stream|matches no streams|Output file does not contain/)
        File.binwrite(output_path, "WEBVTT\n\n")
      end

      def probe_media(path)
        result = command.run(
          @ffprobe, "-v", "error", "-show_entries", "format=start_time,duration:stream=codec_type,start_time,duration",
          "-of", "json", path
        )
        probe = JSON.parse(result.stdout)
        format = probe.fetch("format")
        start = Float(format.fetch("start_time", 0))
        duration = Float(format.fetch("duration"))
        raise InvalidOutput, "ffprobe reported an empty output" unless duration.positive?

        { start: [ start, 0 ].max, finish: [ start, 0 ].max + duration, probe: }
      rescue JSON::ParserError, KeyError, TypeError, ArgumentError
        raise InvalidOutput, "ffprobe did not return usable timing for #{File.basename(path)}"
      end

      def validate_output_timing!(window, starts_at, ends_at)
        raise InvalidOutput, "remuxed part has no duration" unless ends_at > starts_at
        if starts_at > window.starts_at + 2.seconds || ends_at > window.ends_at + 3.seconds
          raise InvalidOutput, "remuxed part timing falls outside its source window"
        end
      end

      def replace_passages!(track, object, cues, duration)
        passages = WebVtt.passages(cues, duration:)
        keys = passages.map { |passage| passage_key(object, passage.start_seconds) }
        track.media_transcript_passages.overlapping(object.starts_at, object.ends_at)
          .where.not(window_key: keys).find_each { |passage| passage.update!(state: "withdrawn") }
        passages.each do |passage|
          record = track.media_transcript_passages.find_or_initialize_by(window_key: passage_key(object, passage.start_seconds))
          record.assign_attributes(
            starts_at: object.starts_at + passage.start_seconds,
            ends_at: object.starts_at + passage.end_seconds,
            text: passage.text,
            state: "published",
            metadata: {
              "caption_object_id" => object.id,
              "caption_checksum" => object.checksum,
              "recipe" => CAPTION_RECIPE
            }
          )
          record.save!
        end
      end

      def passage_key(object, start_seconds)
        absolute_start = object.starts_at + start_seconds
        "caption-window:#{absolute_start.utc.iso8601(3)}"
      end

      def write_concat_list(objects, files, directory, name)
        path = File.join(directory, "#{name}.ffconcat")
        lines = [ "ffconcat version 1.0" ] + objects.map { |object| "file '#{files.fetch(object.id)}'" }
        File.write(path, lines.join("\n") + "\n")
        path
      end

      def concatenate_bytes(paths, output_path)
        File.open(output_path, "wb") do |output|
          paths.each { |path| File.open(path, "rb") { |input| IO.copy_stream(input, output) } }
        end
      end

      def upload_file(key, path, content_type)
        File.open(path, "rb") { |body| storage.upload(key:, body:, content_type:) }
      end

      def create_media_object!(attributes)
        stream.objects.create!(attributes)
      rescue ActiveRecord::RecordNotUnique
        stream.objects.find_by!(identity_key: attributes.fetch(:identity_key))
      end

      def persist_playback_object!(window:, audio_track:, attributes:)
        object = nil
        Warehouse::MediaObject.transaction(requires_new: true) do
          object = stream.objects.create!(attributes)
          stream.objects.where(kind: "playback_part")
            .where.not(id: object.id)
            .where("metadata ->> 'requested_starts_at' = ?", window.starts_at.iso8601(6))
            .where("metadata ->> 'requested_ends_at' = ?", window.ends_at.iso8601(6))
            .where("metadata ->> 'audio_track_id' IS NOT DISTINCT FROM ?", audio_track&.id&.to_s)
            .find_each do |previous|
              previous.update!(metadata: previous.metadata.merge("superseded_by_id" => object.id))
            end
        end
        object
      rescue ActiveRecord::RecordNotUnique
        stream.objects.find_by!(identity_key: attributes.fetch(:identity_key))
      end

      def playback_identity(objects, audio_track)
        digest = derivation_digest(objects, "audio=#{audio_track&.id || 'none'}", RECIPE)
        "playback:#{digest}"
      end

      def caption_identity(objects, track, window)
        digest = derivation_digest(objects, "track=#{track.id}", window.starts_at.iso8601(6), window.ends_at.iso8601(6), CAPTION_RECIPE)
        "caption:#{digest}"
      end

      def derivation_digest(objects, *recipe)
        Digest::SHA256.hexdigest((recipe + objects.flat_map { |object| [ object.id, object.checksum ] }).join("\0"))
      end

      def mark_processed
        state = MediaCaptureState.find_by(media_stream_id: stream.id)
        state&.update!(last_processed_at: Time.current)
      end
    end
  end
end
