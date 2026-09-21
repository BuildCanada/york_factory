require "test_helper"

class Warehouse::Broadcasts::ClipExporterCaptionsTest < ActiveSupport::TestCase
  setup do
    @now = Time.utc(2026, 9, 21, 15)
    @stream = Warehouse::MediaStream.create!(provider: "cpac", external_id: SecureRandom.uuid,
      kind: "event", first_seen_at: @now, last_seen_at: @now)
    @recording = @stream.recordings.create!(recording_key: "event", starts_at: @now, ends_at: @now + 60)
    @clip = MediaClip.create!(user: users(:member), media_recording: @recording, title: "Caption selection",
      starts_at: @now + 10, ends_at: @now + 20, metadata: { "caption_languages" => %w[en fr] })
    @bodies = {}
    bodies = @bodies
    @storage = Object.new
    @storage.define_singleton_method(:download) { |key:| bodies.fetch(key) }
    @exporter = Warehouse::Broadcasts::ClipExporter.new(@clip, storage: @storage)
  end

  test "exports both languages from replacement tracks when older carriers have no coverage" do
    %w[en fr].each do |language|
      add_caption(track(language), 0, 5, "obsolete")
      add_caption(track(language), 8, 22, "current #{language}")
    end

    exported = export_captions(10, 20)
    assert_equal %w[en fr], exported.keys.sort
    assert_includes exported.fetch("en"), "current en"
    assert_includes exported.fetch("fr"), "current fr"
    exported.each_value { |body| assert_not_includes body, "obsolete" }
  end

  test "rejects a gapped older track and uses contiguous replacement coverage" do
    @clip.update!(metadata: { "caption_languages" => [ "en" ] })
    older = track("en")
    add_caption(older, 8, 14, "before gap")
    add_caption(older, 16, 22, "after gap")
    replacement = track("en")
    add_caption(replacement, 8, 15, "replacement first")
    add_caption(replacement, 15, 22, "replacement second")

    body = export_captions(10, 20).fetch("en")
    assert_includes body, "replacement first"
    assert_includes body, "replacement second"
    assert_not_includes body, "gap"
  end

  test "selects coverage using actual keyframe expanded boundaries" do
    @clip.update!(metadata: { "caption_languages" => [ "en" ] })
    add_caption(track("en"), 10, 20, "only requested interval")
    add_caption(track("en"), 8, 22, "expanded interval")

    body = export_captions(8, 22).fetch("en")
    assert_includes body, "expanded interval"
    assert_not_includes body, "only requested"
    assert_includes body, "00:00:00.000 --> 00:00:14.000"
  end

  test "fails visibly if no same language track covers the full interval" do
    @clip.update!(metadata: { "caption_languages" => [ "en" ] })
    add_caption(track("en"), 8, 14, "first carrier")
    add_caption(track("en"), 16, 22, "second carrier")

    error = assert_raises(Warehouse::Broadcasts::ClipExporter::CoverageError) { export_captions(10, 20) }
    assert_match(/missing en captions coverage/, error.message)
  end

  test "default caption languages are deduplicated across carrier tracks" do
    @clip.update!(metadata: {})
    2.times { add_caption(track("en"), 8, 22, "English") }
    add_caption(track("fr"), 8, 22, "French")

    assert_equal %w[en fr], export_captions(10, 20).keys.sort
  end

  private

  def track(language)
    carrier = @stream.tracks.create!(track_key: SecureRandom.uuid, kind: "video", language: "und",
      role: "main", delivery: "separate", first_seen_at: @now, last_seen_at: @now)
    @stream.tracks.create!(track_key: SecureRandom.uuid, kind: "captions", language:, role: "captions",
      parent_track: carrier, delivery: "embedded", first_seen_at: @now, last_seen_at: @now)
  end

  def add_caption(track, from, to, text)
    key = SecureRandom.uuid
    body = "WEBVTT\n\n00:00:00.000 --> 00:00:#{format('%06.3f', to - from)}\n#{text}\n"
    @bodies[key] = body
    track.objects.create!(media_stream: @stream, kind: "caption_file", identity_key: key, object_key: key,
      checksum: Digest::SHA256.hexdigest(body), byte_size: body.bytesize, content_type: "text/vtt",
      starts_at: @now + from, ends_at: @now + to)
  end

  def export_captions(from, to)
    Dir.mktmpdir("clip-caption-test-") do |directory|
      @exporter.send(:export_captions, directory, @now + from, @now + to).to_h do |track, path|
        [ track.language, File.read(path) ]
      end
    end
  end
end
