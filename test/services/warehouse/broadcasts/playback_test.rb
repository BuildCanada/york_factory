require "test_helper"

class Warehouse::Broadcasts::PlaybackTest < ActiveSupport::TestCase
  setup do
    @now = Time.utc(2026, 9, 21, 14)
    @stream = Warehouse::MediaStream.create!(provider: "cpac", external_id: SecureRandom.uuid,
      kind: "event", first_seen_at: @now, last_seen_at: @now)
    @recording = @stream.recordings.create!(recording_key: "event", starts_at: @now)
    @audio = @stream.tracks.create!(track_key: "en", kind: "audio", language: "en", role: "main",
      delivery: "separate", first_seen_at: @now, last_seen_at: @now)
    @storage = Object.new
    @storage.define_singleton_method(:url) { |key:, **| "https://archive.example/#{key}?signed=yes" }
  end

  test "playback keeps missing time and signs only the selected language" do
    first = part("first", 0, 60)
    second = part("second", 70, 130)
    part("other-language", 0, 60, audio_id: "999")
    playback = Warehouse::Broadcasts::Playback.new(@recording, audio_track: @audio, storage: @storage)
    playlist = playback.playlist(gap_url: "/missing")
    assert_equal [ first, second ], playback.parts
    assert_includes playlist, "#EXT-X-GAP\n#EXTINF:10.000000,\n/missing"
    assert_includes playlist, "#EXT-X-DISCONTINUITY"
    assert_includes playlist, "https://archive.example/first?signed=yes"
    assert_includes playlist, "#EXT-X-ENDLIST"
    assert_not_includes playlist, "other-language"
    assert_equal [ [ @now + 60, @now + 70 ] ], playback.gaps
  end

  test "overlapping ready parts are rejected rather than changing the seek timeline" do
    part("first", 0, 61)
    part("second", 60, 120)
    playback = Warehouse::Broadcasts::Playback.new(@recording, audio_track: @audio, storage: @storage)
    assert_raises(ArgumentError) { playback.playlist(gap_url: "/missing") }
  end

  test "rebuilt playback replaces superseded parts without overlapping or deleting source history" do
    original = part("original", 0, 60)
    replacement = part("replacement", 0, 60)
    original.update!(metadata: original.metadata.merge("superseded_by_id" => replacement.id))

    playback = Warehouse::Broadcasts::Playback.new(@recording, audio_track: @audio, storage: @storage)
    assert_equal [ replacement ], playback.parts
    assert_includes playback.playlist(gap_url: "/missing"), "https://archive.example/replacement?signed=yes"
    assert_not_includes playback.playlist(gap_url: "/missing"), "https://archive.example/original?signed=yes"
    assert Warehouse::MediaObject.exists?(original.id)
  end

  test "missing leading and finalized trailing footage remain visible time gaps" do
    @recording.update!(ends_at: @now + 100, state: "partial")
    part("middle", 10, 70)
    playback = Warehouse::Broadcasts::Playback.new(@recording, audio_track: @audio, storage: @storage)
    assert_equal @now, playback.starts_at
    assert_equal [ [ @now, @now + 10 ], [ @now + 70, @now + 100 ] ], playback.gaps
    playlist = playback.playlist(gap_url: "/missing")
    assert_includes playlist, "#EXTINF:10.000000,\n/missing"
    assert_includes playlist, "#EXTINF:30.000000,\n/missing"
  end

  test "caption cues are rebased and clipped to the playback snapshot" do
    track = @stream.tracks.create!(track_key: "cc-fr", kind: "captions", language: "fr", role: "captions",
      delivery: "embedded", first_seen_at: @now, last_seen_at: @now)
    @stream.objects.create!(media_track: track, kind: "caption_file", identity_key: "captions",
      object_key: "captions", checksum: SecureRandom.hex(32), byte_size: 100, content_type: "text/vtt",
      starts_at: @now, ends_at: @now + 60)
    @storage.define_singleton_method(:download) { |key:| "WEBVTT\n\n00:09.000 --> 00:12.000\nBonjour\n" }
    body = Warehouse::Broadcasts::CaptionPresentation.new(track, starts_at: @now + 10,
      ends_at: @now + 30, storage: @storage).call
    assert_includes body, "00:00:00.000 --> 00:00:02.000"
    assert_includes body, "Bonjour"
  end

  test "preview includes two minute lead in and a full thirty minute selection" do
    34.times { |index| part("minute-#{index}", index * 60, (index + 1) * 60) }
    playback = Warehouse::Broadcasts::Playback.new(@recording, audio_track: @audio, at: @now + 180, storage: @storage)
    assert_equal @now + 60, playback.starts_at
    assert_operator playback.ends_at, :>=, @now + 180 + 30.minutes
  end

  private

  def part(key, from, to, audio_id: @audio.id.to_s)
    @stream.objects.create!(kind: "playback_part", identity_key: key, object_key: key,
      checksum: SecureRandom.hex(32), byte_size: 123, content_type: "video/mp2t",
      starts_at: @now + from, ends_at: @now + to, metadata: { "audio_track_id" => audio_id })
  end
end
