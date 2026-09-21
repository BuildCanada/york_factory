module Warehouse
  module Broadcasts
    class Capturer
      Result = Data.define(:captured_count, :target_duration, :end_list)

      DEFAULT_LIMIT = 24
      PER_TRACK_LIMIT = 6
      SEGMENT_MAX_BYTES = 32.megabytes

      class LeaseLost < StandardError; end
      class IntegrityError < StandardError; end

      def initialize(adapter: CpacAdapter.new, http: HttpClient.new, storage: Storage.new, clock: -> { Time.current })
        @adapter = adapter
        @http = http
        @storage = storage
        @clock = clock
      end

      def call(stream:, state:, lease_token:, limit: DEFAULT_LIMIT, source: nil)
        @current_stream = stream
        @capture_source = source&.to_sym
        @historical_timeline_anchor = nil
        now = @clock.call
        descriptors = @adapter.tracks(capture_manifest_url(stream))
        descriptors = descriptors.map { |descriptor| historical_descriptor(descriptor) } if historical?
        tracks = refresh_tracks(stream, descriptors, now:)
        cursor = state.cursor.deep_dup
        cursor["tracks"] ||= {}
        if @adapter.respond_to?(:manifest_snapshot) && (snapshot = @adapter.manifest_snapshot)
          identity = archive_manifest!(stream:, snapshot:, role: "master", state:, lease_token:)
          yield identity if block_given? && identity
        end
        playlists = load_playlists(tracks, stream:, state:, lease_token:) do |identity|
          yield identity if block_given?
        end
        plans = playlists.map do |track, media|
          plan_track(track, media, cursor.fetch("tracks").fetch(track.track_key, {}))
        end
        captured_count = 0

        round_robin(plans, limit:).each do |track, media, segment, epoch, reset_reason|
          identity = identity_key(track, segment, epoch)
          if stream.objects.exists?(identity_key: identity)
            advance_cursor!(state:, lease_token:, cursor:, track:, segment:, epoch:)
            next
          end

          capture_segment!(
            stream:, track:, media:, segment:, epoch:, reset_reason:, identity:,
            state:, lease_token:, cursor:
          )
          captured_count += 1
          yield identity if block_given?
        end

        fully_captured_end = playlists.present? && playlists.all? do |track, media|
          media.end_list && (media.segments.empty? ||
            cursor.dig("tracks", track.track_key, "last_sequence").to_i >= media.segments.last.sequence)
        end
        finalize_recordings!(stream, state:, lease_token:) if fully_captured_end
        Result.new(
          captured_count:,
          target_duration: playlists.values.filter_map(&:target_duration).min || 6,
          end_list: fully_captured_end
        )
      end

      def finalize_stale!(stream:, state:, lease_token:, reason:)
        raise LeaseLost, "capture lease expired before stale finalization" unless state.renew_lease!(token: lease_token, now: @clock.call, ttl: CaptureJob::LEASE_TTL)

        ApplicationRecord.transaction do
          stream.recordings.where(ends_at: nil).find_each do |recording|
            last_end = stream.objects.where(kind: "source_segment")
              .where("starts_at >= ?", recording.starts_at).maximum(:ends_at)
            next unless last_end

            recording.update!(
              ends_at: last_end, state: "partial",
              metadata: recording.metadata.merge("capture_complete" => true, "terminal_reason" => reason)
            )
          end
        end
      end

      private

      def refresh_tracks(stream, descriptors, now:)
        by_key = {}
        descriptors.each do |descriptor|
          track = stream.tracks.find_or_initialize_by(track_key: descriptor.track_key)
          track.assign_attributes(
            kind: descriptor.kind, language: descriptor.language, role: descriptor.role,
            delivery: descriptor.delivery, playlist_url: descriptor.playlist_url,
            codec: descriptor.codec, metadata: descriptor.metadata,
            first_seen_at: track.first_seen_at || now, last_seen_at: now
          )
          track.save!
          by_key[descriptor.track_key] = track
        end
        descriptors.each do |descriptor|
          next unless descriptor.parent_track_key

          track = by_key.fetch(descriptor.track_key)
          parent = by_key.fetch(descriptor.parent_track_key)
          track.update!(parent_track: parent) unless track.parent_track_id == parent.id
        end
        by_key.values
      end

      def historical_descriptor(descriptor)
        metadata = descriptor.metadata.to_h.merge("capture_source" => "historical")
        descriptor.class.new(**descriptor.to_h.merge(
          track_key: "historical:#{descriptor.track_key}",
          parent_track_key: descriptor.parent_track_key && "historical:#{descriptor.parent_track_key}",
          metadata:
        ))
      end

      def load_playlists(tracks, stream:, state:, lease_token:)
        tracks.filter_map do |track|
          next if track.playlist_url.blank?

          response = http_get(stream, track.playlist_url, max_bytes: 2.megabytes)
          identity = archive_manifest!(
            stream:, snapshot: { body: response.body, content_type: response.content_type, url: response.url },
            role: "media", track:, state:, lease_token:
          )
          yield identity if identity && block_given?
          media = Hls.parse(
            response.body, base_url: response.url,
            timeline_anchor: historical? ? historical_timeline_anchor : nil
          )
          raise Hls::ParseError, "#{track.track_key} resolved to another master playlist" unless media.is_a?(Hls::Media)
          if historical? && !media.end_list
            raise Hls::UnsupportedTransport,
              "#{track.track_key} archive is not finalized; retry after the programme ends"
          end
          if historical? && media.end_list && media.segments.empty?
            raise Hls::UnsupportedTransport, "#{track.track_key} historical playlist contains no media segments"
          end

          [ track, media ]
        end.to_h
      end

      def plan_track(track, media, track_cursor)
        previous_sequence = integer_or_nil(track_cursor["last_sequence"])
        previous_uri = track_cursor["last_uri"]
        epoch = track_cursor.fetch("epoch", 0).to_i
        reset_reason = nil
        previous_end = parse_time(track_cursor["last_end_at"])
        if previous_sequence && playlist_reset?(media, previous_sequence, previous_uri, previous_end)
          epoch += 1
          reset_reason = "playlist_sequence_or_uri_reset"
          previous_sequence = nil
        end

        pending = media.segments.select { |segment| previous_sequence.nil? || segment.sequence > previous_sequence }
        pending = pending.last(PER_TRACK_LIMIT) if previous_sequence.nil? && !historical?
        { track:, media:, segments: pending, epoch:, reset_reason: }
      end

      def playlist_reset?(media, previous_sequence, previous_uri, previous_end)
        return false if media.segments.empty?
        return true if media.segments.last.sequence < previous_sequence

        matching = media.segments.find { |segment| segment.sequence == previous_sequence }
        return false unless matching
        return true if previous_uri.present? && matching.uri != previous_uri

        previous_end && (matching.ends_at - previous_end).abs > 0.05
      end

      def round_robin(plans, limit:)
        queues = plans.map { |plan| plan.merge(segments: plan.fetch(:segments).dup) }
        result = []
        while result.length < limit && (plan = queues.find { |candidate| candidate.fetch(:segments).any? })
          result << [
            plan.fetch(:track), plan.fetch(:media), plan.fetch(:segments).shift,
            plan.fetch(:epoch), plan.fetch(:reset_reason)
          ]
          plan[:reset_reason] = nil
          queues.rotate!(queues.index(plan) + 1)
        end
        result
      end

      def capture_segment!(stream:, track:, media:, segment:, epoch:, reset_reason:, identity:, state:, lease_token:, cursor:)
        raise LeaseLost, "capture lease expired before download" unless state.lease_owned?(lease_token, now: @clock.call)

        headers = {}
        if segment.byte_range
          offset = segment.byte_range.fetch("offset", 0)
          length = segment.byte_range.fetch("length")
          headers["Range"] = "bytes=#{offset}-#{offset + length - 1}"
        end
        response = http_get(stream, segment.uri, max_bytes: SEGMENT_MAX_BYTES, headers:)
        checksum = Digest::SHA256.hexdigest(response.body)
        key = object_key(stream, track, segment, epoch, checksum, response.content_type)
        @storage.upload(key:, body: response.body, content_type: response.content_type || "application/octet-stream")

        committed = false
        ApplicationRecord.transaction do
          raise LeaseLost, "capture lease expired after upload" unless state.renew_lease!(token: lease_token, now: @clock.call, ttl: CaptureJob::LEASE_TTL)

          track_cursor = cursor.fetch("tracks").fetch(track.track_key, {})
          metadata = segment_metadata(segment, media, track_cursor, reset_reason)
          object = stream.objects.find_or_initialize_by(identity_key: identity)
          if object.persisted? && object.checksum != checksum
            raise IntegrityError, "identity #{identity} changed checksum"
          end
          object.assign_attributes(
            media_track: track, kind: "source_segment", object_key: key, checksum:,
            byte_size: response.body.bytesize, content_type: response.content_type || "application/octet-stream",
            starts_at: segment.starts_at, ends_at: segment.ends_at, epoch:, sequence: segment.sequence,
            metadata:
          )
          object.save!
          update_recording!(stream, track, segment, epoch, metadata)

          set_track_cursor(cursor, track, segment, epoch)
          unless state.update_cursor!(token: lease_token, now: @clock.call, cursor:, attrs: { last_captured_at: @clock.call })
            raise ActiveRecord::Rollback
          end
          committed = true
        end
        raise LeaseLost, "capture lease was fenced before commit" unless committed
      end

      def archive_manifest!(stream:, snapshot:, role:, state:, lease_token:, track: nil)
        checksum = Digest::SHA256.hexdigest(snapshot.fetch(:body))
        identity = "manifest/#{capture_namespace}/#{role}/#{track&.id || 'master'}/#{checksum}"
        return if stream.objects.exists?(identity_key: identity)
        raise LeaseLost, "capture lease expired before manifest upload" unless state.lease_owned?(lease_token, now: @clock.call)

        safe_track = track&.track_key&.gsub(/[^a-zA-Z0-9_.-]+/, "-") || "master"
        key = "broadcasts/#{stream.provider}/#{stream.external_id}/manifests/#{capture_namespace}/#{safe_track}-#{checksum.first(16)}.m3u8"
        @storage.upload(
          key:, body: snapshot.fetch(:body),
          content_type: snapshot[:content_type] || "application/vnd.apple.mpegurl"
        )
        committed = false
        ApplicationRecord.transaction do
          raise LeaseLost, "capture lease expired after manifest upload" unless state.renew_lease!(token: lease_token, now: @clock.call, ttl: CaptureJob::LEASE_TTL)

          stream.objects.create!(
            media_track: track, kind: "manifest", identity_key: identity, object_key: key,
            checksum:, byte_size: snapshot.fetch(:body).bytesize,
            content_type: snapshot[:content_type] || "application/vnd.apple.mpegurl",
            metadata: {
              "source_uri" => snapshot.fetch(:url), "playlist_role" => role,
              "capture_source" => capture_namespace
            }
          )
          committed = true
        end
        raise LeaseLost, "capture lease was fenced before manifest commit" unless committed

        identity
      end

      def advance_cursor!(state:, lease_token:, cursor:, track:, segment:, epoch:)
        set_track_cursor(cursor, track, segment, epoch)
        return if state.update_cursor!(token: lease_token, now: @clock.call, cursor:)

        raise LeaseLost, "capture lease was fenced while reconciling cursor"
      end

      def set_track_cursor(cursor, track, segment, epoch)
        cursor["tracks"][track.track_key] = {
          "epoch" => epoch, "last_sequence" => segment.sequence, "last_uri" => segment.uri,
          "last_end_at" => segment.ends_at.iso8601(6), "playlist_url" => track.playlist_url,
          "discontinuity_sequence" => segment.discontinuity_sequence
        }
      end

      def update_recording!(stream, track, segment, epoch, object_metadata)
        recording_key = if stream.kind == "continuous"
          "utc-#{segment.starts_at.utc.to_date.iso8601}"
        elsif historical?
          "historical-event-#{stream.external_id}"
        else
          "event-#{stream.external_id}"
        end
        recording = stream.recordings.find_or_initialize_by(recording_key:)
        recording.starts_at = [ recording.starts_at, segment.starts_at ].compact.min
        recording.title_en ||= stream.title_en
        recording.title_fr ||= stream.title_fr
        recording.state ||= "open"
        metadata = recording.metadata.deep_dup
        metadata["capture_source"] = capture_namespace
        if object_metadata["timeline_is_original_broadcast_time"] == false
          metadata["timeline_is_original_broadcast_time"] = false
          metadata["publication_time_anchor"] = object_metadata.fetch("publication_time_anchor")
          metadata["timeline_note"] = "Media timestamps are relative to the provider publication time, not the original broadcast time."
        end
        if object_metadata["gap_before"] || object_metadata["timeline_gap_seconds"].to_f > 0.05
          metadata["capture_gaps"] ||= []
          gap_key = "#{track.id}:#{epoch}:#{segment.sequence}"
          unless metadata.fetch("capture_gaps").any? { |gap| gap["key"] == gap_key }
            metadata["capture_gaps"] << {
              "key" => gap_key, "track_id" => track.id, "at" => segment.starts_at.iso8601(6),
              "missing_sequences" => object_metadata["gap_before"],
              "timeline_gap_seconds" => object_metadata["timeline_gap_seconds"]
            }.compact
          end
        end
        recording.metadata = metadata
        recording.save!
        finalize_older_continuous_recordings!(stream, except: recording) if stream.kind == "continuous"
      end

      def finalize_older_continuous_recordings!(stream, except:)
        stream.recordings.where(ends_at: nil).where.not(id: except.id).find_each do |recording|
          last_end = stream.objects.where(kind: "source_segment").where("starts_at >= ?", recording.starts_at)
            .where("starts_at < ?", except.starts_at).maximum(:ends_at)
          finish_recording!(recording, ends_at: last_end) if last_end
        end
      end

      def finalize_recordings!(stream, state:, lease_token:)
        raise LeaseLost, "capture lease expired before recording finalization" unless state.renew_lease!(token: lease_token, now: @clock.call, ttl: CaptureJob::LEASE_TTL)

        recordings = stream.recordings.where(ends_at: nil)
        recordings = recordings.where(recording_key: "historical-event-#{stream.external_id}") if historical?
        recordings = recordings.order(:starts_at).to_a
        recordings.each_with_index do |recording, index|
          scope = stream.objects.where(kind: "source_segment").where("starts_at >= ?", recording.starts_at)
          scope = scope.where("starts_at < ?", recordings[index + 1].starts_at) if recordings[index + 1]
          finish_recording!(recording, ends_at: scope.maximum(:ends_at)) if scope.maximum(:ends_at)
        end
      end

      def finish_recording!(recording, ends_at:)
        metadata = recording.metadata.merge("capture_complete" => true)
        recording.update!(
          ends_at:, state: metadata.fetch("capture_gaps", []).any? ? "partial" : "finalized",
          metadata:
        )
      end

      def segment_metadata(segment, media, track_cursor, reset_reason)
        previous_sequence = integer_or_nil(track_cursor["last_sequence"])
        previous_end = parse_time(track_cursor["last_end_at"])
        metadata = {
          "duration" => segment.duration, "discontinuity" => segment.discontinuity,
          "discontinuity_sequence" => segment.discontinuity_sequence, "source_uri" => segment.uri,
          "byte_range" => segment.byte_range, "anchor_source" => segment.anchor_source,
          "provider_timestamp_map" => media.timestamp_map, "init_uri" => segment.init_uri
        }.compact
        if segment.anchor_source.start_with?("program_date_time")
          metadata["provider_program_date_time"] = segment.starts_at.iso8601(6)
        else
          metadata["publication_time_anchor"] = historical_timeline_anchor.iso8601(6)
          metadata["relative_start_seconds"] = segment.relative_start
          metadata["relative_end_seconds"] = segment.relative_end
          metadata["timeline_is_original_broadcast_time"] = false
        end
        if previous_sequence && segment.sequence > previous_sequence + 1
          metadata["gap_before"] = { "first_missing_sequence" => previous_sequence + 1, "last_missing_sequence" => segment.sequence - 1 }
        end
        if previous_end && (gap = segment.starts_at - previous_end).abs > 0.05
          metadata["timeline_gap_seconds"] = gap
        end
        metadata["reset_reason"] = reset_reason if reset_reason
        metadata
      end

      def identity_key(track, segment, epoch)
        range = segment.byte_range ? "#{segment.byte_range['offset'] || 0}-#{segment.byte_range['length']}" : "full"
        "source_segment/#{capture_namespace}/#{track.id}/#{epoch}/#{segment.discontinuity_sequence}/#{segment.sequence}/#{range}"
      end

      def object_key(stream, track, segment, epoch, checksum, content_type)
        extension = case content_type
        when /mp2t/ then "ts"
        when /mp4/ then "m4s"
        else File.extname(URI.parse(segment.uri).path).delete_prefix(".").presence || "bin"
        end
        safe_track = track.track_key.gsub(/[^a-zA-Z0-9_.-]+/, "-")
        "broadcasts/#{stream.provider}/#{stream.external_id}/source/#{capture_namespace}/#{safe_track}/e#{epoch}-s#{segment.sequence}-#{checksum.first(16)}.#{extension}"
      end

      def integer_or_nil(value)
        Integer(value) if value.present?
      rescue ArgumentError, TypeError
        nil
      end

      def parse_time(value)
        Time.iso8601(value) if value.present?
      rescue ArgumentError
        nil
      end

      def http_get(stream, url, **options)
        if stream.provider == "cpac"
          options[:allowed_hosts] = CpacAdapter::ALLOWED_HOSTS
          options[:allowed_host_suffixes] = CpacAdapter::ALLOWED_HOST_SUFFIXES
        end
        @http.get(url, **options)
      end

      def historical?
        @capture_source == :historical || @current_stream&.kind == "on_demand"
      end

      def capture_namespace
        historical? ? "historical" : "live"
      end

      def capture_manifest_url(stream)
        if historical? && stream.metadata["historical_manifest_url"].present?
          stream.metadata.fetch("historical_manifest_url")
        else
          stream.manifest_url
        end
      end

      def historical_timeline_anchor
        @historical_timeline_anchor ||= begin
          value = @current_stream.metadata["publication_time"] ||
            @current_stream.metadata["published_at"] ||
            @current_stream.metadata["provider_published_at"] ||
            @current_stream.scheduled_start_at
          Time.iso8601(value.to_s).utc if value.present?
        rescue ArgumentError
          nil
        end
      end
    end
  end
end
