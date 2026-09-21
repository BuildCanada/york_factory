require "test_helper"

class Warehouse::Broadcasts::ProcessorTest < ActiveJob::TestCase
  class LocalStorage
    attr_reader :objects

    def initialize
      @objects = {}
    end

    def upload(key:, body:, content_type:)
      objects[key] = body.respond_to?(:read) ? body.read : body.to_s
    end

    def download_to(key:, path:)
      File.binwrite(path, objects.fetch(key))
    end

    def download(key:)
      objects.fetch(key)
    end
  end

  setup do
    @ffmpeg = ENV.fetch("FFMPEG_BIN") { ENV.fetch("PATH").split(File::PATH_SEPARATOR).map { File.join(_1, "ffmpeg") }.find { File.executable?(_1) } }
    @ffprobe = ENV.fetch("FFPROBE_BIN") { ENV.fetch("PATH").split(File::PATH_SEPARATOR).map { File.join(_1, "ffprobe") }.find { File.executable?(_1) } }
    skip "ffmpeg is not installed" unless @ffmpeg && @ffprobe && File.executable?(@ffmpeg) && File.executable?(@ffprobe)

    @now = Time.utc(2026, 9, 21, 15)
    @storage = LocalStorage.new
    @stream = Warehouse::MediaStream.create!(
      provider: "cpac", external_id: "processor-#{SecureRandom.hex(4)}", kind: "event",
      first_seen_at: @now, last_seen_at: @now
    )
    @video = @stream.tracks.create!(
      track_key: "video:720p", kind: "video", language: "und", role: "main", delivery: "separate",
      first_seen_at: @now, last_seen_at: @now
    )
  end

  test "remuxes only a complete source window and is idempotent" do
    Dir.mktmpdir("processor-fixture-") do |directory|
      2.times { |index| add_video_segment(directory, index, duration: 3) }
      processor(target_duration: 7).call
      assert_empty @stream.objects.where(kind: "playback_part")

      add_video_segment(directory, 2, duration: 3)
      assert_equal 1, processor(target_duration: 7).call
      part = @stream.objects.find_by!(kind: "playback_part")
      assert_equal @video.id, part.media_track_id
      assert_nil part.metadata["audio_track_id"]
      assert_equal 3, part.metadata.fetch("source_object_ids").length
      assert_in_delta 9, part.ends_at - part.starts_at, 0.5
      assert @storage.objects.fetch(part.object_key).bytesize.positive?

      assert_equal 0, processor(target_duration: 7).call
      assert_equal 1, @stream.objects.where(kind: "playback_part").count
    end
  end

  test "extracts CPAC caption fields with explicit decoder options" do
    track = @stream.tracks.create!(
      track_key: "captions:cc:field2", kind: "captions", language: "fr", role: "captions",
      delivery: "embedded", parent_track: @video, first_seen_at: @now, last_seen_at: @now,
      metadata: { "caption_field" => 2 }
    )
    fake_command = Object.new
    captured = nil
    fake_command.define_singleton_method(:run) do |*argv|
      captured = argv
      File.binwrite(argv.last, "WEBVTT\n\n") if argv.last.end_with?(".vtt")
      Struct.new(:stdout).new("")
    end
    instance = processor(command: fake_command)
    instance.send(:extract_captions, "/tmp/carrier.ts", "/tmp/captions-test.vtt", track.metadata.fetch("caption_field"))

    assert_includes captured, "-data_field"
    assert_equal "second", captured[captured.index("-data_field") + 1]
    assert_includes captured, "movie='/tmp/carrier.ts'[out0+subcc]"
  end

  test "unusable probe output is classified for bounded job retries" do
    [ "not json", '{"format":{"duration":"not a number"}}', '{"format":{"duration":"0"}}' ].each do |body|
      command = Object.new
      command.define_singleton_method(:run) { |*| Struct.new(:stdout).new(body) }
      assert_raises(Warehouse::Broadcasts::Processor::InvalidOutput) do
        processor(command:).send(:probe_media, "/tmp/broadcast-test.ts")
      end
    end
  end

  test "advances through more complete windows than one bounded batch" do
    Dir.mktmpdir("processor-backlog-") do |directory|
      5.times { |index| add_video_segment(directory, index, duration: 1) }
      first = processor(target_duration: 1)
      assert_equal 2, first.call
      assert first.more_work?

      second = processor(target_duration: 1)
      assert_equal 2, second.call
      assert second.more_work?

      third = processor(target_duration: 1)
      assert_equal 1, third.call
      assert_not third.more_work?
      assert_equal 5, @stream.objects.where(kind: "playback_part").count
    end
  end

  test "exports a verified keyframe-aligned mp4 and is idempotent" do
    Dir.mktmpdir("processor-clip-") do |directory|
      3.times { |index| add_video_segment(directory, index, duration: 3) }
      assert_equal 1, processor(target_duration: 7).call
      recording = @stream.recordings.create!(
        recording_key: "event", starts_at: @now, ends_at: @now + 9.seconds, state: "finalized"
      )
      clip = MediaClip.create!(
        user: users(:member), media_recording: recording, title: "Question period",
        starts_at: @now + 2.2.seconds, ends_at: @now + 6.2.seconds,
        metadata: { "caption_languages" => [] }
      )

      exporter = Warehouse::Broadcasts::ClipExporter.new(
        clip, storage: @storage, ffmpeg: @ffmpeg, ffprobe: @ffprobe
      )
      exporter.call
      clip.reload
      assert_equal "ready", clip.state
      assert clip.file.attached?
      assert_operator clip.actual_starts_at, :<=, clip.starts_at
      assert_operator clip.actual_ends_at, :>=, clip.ends_at - 0.1.seconds
      assert_equal [], clip.metadata.fetch("caption_languages")

      assert_no_difference -> { ActiveStorage::Attachment.count } do
        exporter.call
      end
    end
  end

  test "exports precise boundaries without rounding back to a sparse keyframe" do
    Dir.mktmpdir("processor-exact-clip-") do |directory|
      3.times { |index| add_video_segment(directory, index, duration: 3) }
      audio = @stream.tracks.create!(
        track_key: "audio:en", kind: "audio", language: "en", role: "main", delivery: "separate",
        first_seen_at: @now, last_seen_at: @now
      )
      3.times do |index|
        add_audio_segment(directory, audio, "exact-#{index}", starts_at: @now + index * 3.seconds,
          ends_at: @now + (index + 1) * 3.seconds, frequency: 440)
      end
      assert_equal 1, processor(target_duration: 7).call
      recording = @stream.recordings.create!(
        recording_key: "event", starts_at: @now, ends_at: @now + 9.seconds, state: "finalized"
      )
      @stream.tracks.create!(track_key: "captions:en:obsolete", kind: "captions", language: "en", role: "captions",
        delivery: "embedded", parent_track: @video, first_seen_at: @now, last_seen_at: @now)
      captions = @stream.tracks.create!(
        track_key: "captions:en", kind: "captions", language: "en", role: "captions",
        delivery: "embedded", first_seen_at: @now, last_seen_at: @now
      )
      caption_body = "WEBVTT\n\n00:02.000 --> 00:02.500\nLeading cue\n\n00:06.000 --> 00:06.500\nTrailing cue\n"
      @storage.objects["captions/exact.vtt"] = caption_body
      @stream.objects.create!(
        media_track: captions, kind: "caption_file", identity_key: "captions:exact",
        object_key: "captions/exact.vtt", checksum: Digest::SHA256.hexdigest(caption_body),
        byte_size: caption_body.bytesize, content_type: "text/vtt",
        starts_at: @now, ends_at: @now + 9.seconds
      )
      clip = MediaClip.create!(
        user: users(:member), media_recording: recording, media_track: audio, title: "Precise question period",
        starts_at: @now + 2.2.seconds, ends_at: @now + 6.2.seconds,
        metadata: { "caption_languages" => [ "en" ], "export_mode" => "exact" }
      )

      Warehouse::Broadcasts::ClipExporter.new(
        clip, storage: @storage, ffmpeg: @ffmpeg, ffprobe: @ffprobe
      ).call
      clip.reload

      assert_equal "ready", clip.state
      assert_equal clip.starts_at, clip.actual_starts_at
      assert_in_delta 4.0, clip.actual_ends_at - clip.actual_starts_at, 0.105
      assert_equal "exact-h264-aac-v1", clip.metadata.fetch("recipe")
      assert_operator clip.actual_starts_at, :>, @now + 2.seconds,
        "precise export rounded back to the preceding keyframe"
      assert_equal 1, clip.captions.count
      rendered_captions = clip.captions.first.download
      assert_includes rendered_captions, "00:00:00.000 --> 00:00:00.300"
      rendered_cues = Warehouse::Broadcasts::WebVtt.parse(rendered_captions)
      assert_in_delta clip.actual_ends_at - clip.actual_starts_at, rendered_cues.last.end_seconds, 0.001

      clip.file.blob.open do |file|
        probe = Warehouse::Broadcasts::Command.new.run(
          @ffprobe, "-v", "error", "-show_entries", "stream=codec_name,codec_type", "-of", "json", file.path
        )
        video = JSON.parse(probe.stdout).fetch("streams").find { |stream| stream["codec_type"] == "video" }
        assert_equal "h264", video.fetch("codec_name")
      end
    end
  end

  test "trims an earlier audio source to the common video window" do
    Dir.mktmpdir("processor-av-") do |directory|
      add_video_segment(directory, 0, duration: 3)
      audio = @stream.tracks.create!(
        track_key: "audio:en", kind: "audio", language: "en", role: "main", delivery: "separate",
        first_seen_at: @now, last_seen_at: @now
      )
      path = File.join(directory, "audio.aac")
      Warehouse::Broadcasts::Command.new.run(
        @ffmpeg, "-nostdin", "-hide_banner", "-loglevel", "error",
        "-f", "lavfi", "-i", "aevalsrc=if(lt(t\\,0.5)\\,0\\,sin(2*PI*440*(t-0.5))):s=48000",
        "-t", "4", "-c:a", "aac", "-f", "adts", "-y", path
      )
      bytes = File.binread(path)
      key = "source/#{SecureRandom.hex(8)}.aac"
      @storage.objects[key] = bytes
      @stream.objects.create!(
        media_track: audio, kind: "source_segment", identity_key: "audio:0", object_key: key,
        checksum: Digest::SHA256.hexdigest(bytes), byte_size: bytes.bytesize, content_type: "audio/aac",
        starts_at: @now - 0.5.seconds, ends_at: @now + 3.5.seconds, epoch: 0, sequence: 0
      )

      assert_equal 1, processor(target_duration: 3).call
      part = @stream.objects.find_by!(kind: "playback_part")
      assert_equal audio.id.to_s, part.metadata.fetch("audio_track_id")
      streams = part.metadata.dig("ffprobe", "streams")
      assert_equal %w[audio video], streams.map { |item| item.fetch("codec_type") }.sort
      starts = streams.map { |item| Float(item.fetch("start_time")) }
      assert_operator starts.max - starts.min, :<=, 0.05, "stream starts were #{starts.inspect}"
      assert_operator part.ends_at - part.starts_at, :<=, 3.05

      output = File.join(directory, "trimmed-playback.ts")
      File.binwrite(output, @storage.objects.fetch(part.object_key))
      pcm = File.join(directory, "trimmed-first-quarter-second.pcm")
      Warehouse::Broadcasts::Command.new.run(
        @ffmpeg, "-nostdin", "-hide_banner", "-loglevel", "error", "-i", output,
        "-map", "0:a:0", "-t", "0.25", "-ac", "1", "-ar", "8000", "-f", "s16le", "-y", pcm
      )
      assert_operator File.binread(pcm).unpack("s<*").map(&:abs).max, :>, 1_000,
        "audio trim left the leading half-second of silence in place"
    end
  end

  test "does not copy a stale audio segment whose last frame overlaps the video window" do
    Dir.mktmpdir("processor-av-overlap-") do |directory|
      add_video_segment(directory, 0, duration: 3)
      audio = @stream.tracks.create!(
        track_key: "audio:en", kind: "audio", language: "en", role: "main", delivery: "separate",
        first_seen_at: @now, last_seen_at: @now
      )
      stale = add_audio_segment(directory, audio, "stale", starts_at: @now - 3.seconds,
        ends_at: @now + 0.02.seconds, frequency: 220)
      current = add_audio_segment(directory, audio, "current", starts_at: @now + 0.02.seconds,
        ends_at: @now + 3.02.seconds, frequency: 880)

      assert_equal 1, processor(target_duration: 3).call
      part = @stream.objects.find_by!(kind: "playback_part")
      assert_not_includes part.metadata.fetch("source_object_ids"), stale.id
      assert_includes part.metadata.fetch("source_object_ids"), current.id

      output = File.join(directory, "playback.ts")
      File.binwrite(output, @storage.objects.fetch(part.object_key))
      pcm = File.join(directory, "first-half-second.pcm")
      Warehouse::Broadcasts::Command.new.run(
        @ffmpeg, "-nostdin", "-hide_banner", "-loglevel", "error", "-i", output,
        "-map", "0:a:0", "-t", "0.5", "-ac", "1", "-ar", "8000", "-f", "s16le", "-y", pcm
      )
      samples = File.binread(pcm).unpack("s<*")
      zero_crossings = samples.each_cons(2).count { |left, right| (left.negative? && right >= 0) || (left >= 0 && right.negative?) }
      assert_operator zero_crossings, :>, 600, "expected current 880 Hz audio, got #{zero_crossings} zero crossings"
    end
  end

  test "processes a new video carrier after the original rendition retires" do
    Dir.mktmpdir("processor-rendition-") do |directory|
      add_video_segment(directory, 0, duration: 1)
      assert_equal 1, processor(target_duration: 1).call

      replacement_seen_at = @now + 1.second
      replacement = @stream.tracks.create!(
        track_key: "video:replacement", kind: "video", language: "und", role: "main", delivery: "separate",
        first_seen_at: replacement_seen_at, last_seen_at: replacement_seen_at
      )
      path = File.join(directory, "replacement.ts")
      Warehouse::Broadcasts::Command.new.run(
        @ffmpeg, "-nostdin", "-hide_banner", "-loglevel", "error",
        "-f", "lavfi", "-i", "testsrc=size=160x90:rate=10",
        "-t", "1", "-c:v", "libx264", "-pix_fmt", "yuv420p",
        "-g", "10", "-sc_threshold", "0", "-f", "mpegts", "-y", path
      )
      bytes = File.binread(path)
      key = "source/#{SecureRandom.hex(8)}.ts"
      @storage.objects[key] = bytes
      @stream.objects.create!(
        media_track: replacement, kind: "source_segment", identity_key: "replacement:0", object_key: key,
        checksum: Digest::SHA256.hexdigest(bytes), byte_size: bytes.bytesize, content_type: "video/mp2t",
        starts_at: replacement_seen_at, ends_at: replacement_seen_at + 1.second, epoch: 1, sequence: 0
      )

      assert_equal 1, processor(target_duration: 1).call
      assert_equal [ @video.id, replacement.id ].sort,
        @stream.objects.where(kind: "playback_part").pluck(:media_track_id).sort
    end
  end

  private

  def processor(command: nil, target_duration: 8)
    Warehouse::Broadcasts::Processor.new(
      @stream, storage: @storage, command:, ffmpeg: @ffmpeg, ffprobe: @ffprobe,
      target_duration:, max_windows: 2
    )
  end

  def add_video_segment(directory, index, duration:)
    path = File.join(directory, "segment-#{index}.ts")
    Warehouse::Broadcasts::Command.new.run(
      @ffmpeg, "-nostdin", "-hide_banner", "-loglevel", "error",
      "-f", "lavfi", "-i", "testsrc=size=160x90:rate=10",
      "-t", duration.to_s, "-c:v", "libx264", "-pix_fmt", "yuv420p",
      "-g", "20", "-sc_threshold", "0", "-f", "mpegts", "-y", path
    )
    bytes = File.binread(path)
    key = "source/#{SecureRandom.hex(8)}.ts"
    @storage.objects[key] = bytes
    @stream.objects.create!(
      media_track: @video, kind: "source_segment", identity_key: "video:#{index}", object_key: key,
      checksum: Digest::SHA256.hexdigest(bytes), byte_size: bytes.bytesize, content_type: "video/mp2t",
      starts_at: @now + index * duration, ends_at: @now + (index + 1) * duration,
      epoch: 0, sequence: index
    )
  end


  def add_audio_segment(directory, track, name, starts_at:, ends_at:, frequency:)
    path = File.join(directory, "#{name}.aac")
    Warehouse::Broadcasts::Command.new.run(
      @ffmpeg, "-nostdin", "-hide_banner", "-loglevel", "error",
      "-f", "lavfi", "-i", "sine=frequency=#{frequency}:sample_rate=48000",
      "-t", format("%.6f", ends_at - starts_at), "-c:a", "aac", "-f", "adts", "-y", path
    )
    bytes = File.binread(path)
    key = "source/#{SecureRandom.hex(8)}.aac"
    @storage.objects[key] = bytes
    @stream.objects.create!(
      media_track: track, kind: "source_segment", identity_key: "audio:#{name}", object_key: key,
      checksum: Digest::SHA256.hexdigest(bytes), byte_size: bytes.bytesize, content_type: "audio/aac",
      starts_at:, ends_at:, epoch: 0, sequence: name == "stale" ? -1 : 0
    )
  end
end
