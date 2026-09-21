require "test_helper"

class Warehouse::Broadcasts::CapturerTest < ActiveSupport::TestCase
  Track = Warehouse::Broadcasts::CpacAdapter::Track
  Response = Warehouse::Broadcasts::HttpClient::Response

  setup do
    @now = Time.iso8601("2026-09-21T15:01:00Z")
    @stream = Warehouse::MediaStream.create!(
      provider: "cpac", external_id: SecureRandom.uuid, kind: "event",
      manifest_url: "https://media.example.test/master.m3u8",
      first_seen_at: @now, last_seen_at: @now
    )
    @state = MediaCaptureState.create!(media_stream: @stream, enabled: true, next_poll_at: @now)
    @token = @state.claim!(now: @now, ttl: 2.minutes)
    @storage = MemoryStorage.new
  end

  test "archives immutable source objects and resumes from the durable cursor" do
    capturer = build_capturer(media_fixture)

    result = capturer.call(stream: @stream, state: @state, lease_token: @token)

    assert_equal 3, result.captured_count
    assert_equal 3, @stream.objects.where(kind: "source_segment").count
    assert_equal 1, @stream.objects.where(kind: "manifest").count
    first = @stream.objects.where(kind: "source_segment").order(:sequence).first
    assert_equal "source_segment", first.kind
    assert_equal 100, first.sequence
    assert_equal "program_date_time", first.metadata.fetch("anchor_source")
    assert_equal "MPEGTS=4595652783,LOCAL=2026-09-21T14:55:34.346100Z", first.metadata.fetch("provider_timestamp_map")
    assert_equal first.checksum, Digest::SHA256.hexdigest(@storage.objects.fetch(first.object_key).fetch(:body))
    assert_equal 102, @state.reload.cursor.dig("tracks", "video:720p:test", "last_sequence")

    second = capturer.call(stream: @stream, state: @state, lease_token: @token)
    assert_equal 0, second.captured_count
    assert_equal 4, @stream.objects.count
  end

  test "records a provider sequence and wall-clock gap without rebasing time" do
    build_capturer(media_fixture).call(stream: @stream, state: @state, lease_token: @token)
    later = <<~M3U8
      #EXTM3U
      #EXT-X-MEDIA-SEQUENCE:105
      #EXT-X-TARGETDURATION:6
      #EXT-X-PROGRAM-DATE-TIME:2026-09-21T15:02:00Z
      #EXTINF:6,
      segment-105.ts
    M3U8

    build_capturer(later).call(stream: @stream, state: @state, lease_token: @token)

    object = @stream.objects.find_by!(sequence: 105)
    assert_equal({ "first_missing_sequence" => 103, "last_missing_sequence" => 104 }, object.metadata.fetch("gap_before"))
    assert_in_delta 113.6, object.metadata.fetch("timeline_gap_seconds"), 0.001
    assert_equal Time.iso8601("2026-09-21T15:02:00Z"), object.starts_at
  end

  test "starts a new epoch when a playlist sequence resets" do
    build_capturer(media_fixture).call(stream: @stream, state: @state, lease_token: @token)
    reset = <<~M3U8
      #EXTM3U
      #EXT-X-MEDIA-SEQUENCE:1
      #EXT-X-TARGETDURATION:6
      #EXT-X-PROGRAM-DATE-TIME:2026-09-21T16:00:00Z
      #EXTINF:6,
      restarted-1.ts
    M3U8

    build_capturer(reset).call(stream: @stream, state: @state, lease_token: @token)

    object = @stream.objects.find_by!(sequence: 1)
    assert_equal 1, object.epoch
    assert_equal "playlist_sequence_or_uri_reset", object.metadata.fetch("reset_reason")
    assert_equal Time.iso8601("2026-09-21T16:00:00Z"), object.starts_at
  end

  test "starts a new epoch when a provider reuses sequence and URI with a new timeline" do
    build_capturer(media_fixture).call(stream: @stream, state: @state, lease_token: @token)
    reused = <<~M3U8
      #EXTM3U
      #EXT-X-MEDIA-SEQUENCE:102
      #EXT-X-TARGETDURATION:6
      #EXT-X-PROGRAM-DATE-TIME:2026-09-21T16:00:00Z
      #EXTINF:6.4,
      segment-102.ts
    M3U8

    build_capturer(reused).call(stream: @stream, state: @state, lease_token: @token)

    objects = @stream.objects.where(kind: "source_segment", sequence: 102).order(:epoch)
    assert_equal [ 0, 1 ], objects.pluck(:epoch)
    assert_equal Time.iso8601("2026-09-21T16:00:00Z"), objects.last.starts_at
    assert_equal "playlist_sequence_or_uri_reset", objects.last.metadata.fetch("reset_reason")
  end

  test "finalizes a complete event recording at the source timeline end" do
    complete = <<~M3U8
      #EXTM3U
      #EXT-X-MEDIA-SEQUENCE:1
      #EXT-X-TARGETDURATION:6
      #EXT-X-PROGRAM-DATE-TIME:2026-09-21T16:00:00Z
      #EXTINF:6,
      segment-1.ts
      #EXTINF:6,
      segment-2.ts
      #EXT-X-ENDLIST
    M3U8

    result = build_capturer(complete).call(stream: @stream, state: @state, lease_token: @token)

    assert result.end_list
    recording = @stream.recordings.sole
    assert_equal "finalized", recording.state
    assert_equal Time.iso8601("2026-09-21T16:00:00Z"), recording.starts_at
    assert_equal Time.iso8601("2026-09-21T16:00:12Z"), recording.ends_at
    assert recording.metadata.fetch("capture_complete")
  end

  test "captures an on-demand playlist from the beginning in bounded resumable calls" do
    @stream.update!(
      kind: "on_demand",
      metadata: { "provider_published_at" => "2020-01-02T00:00:00Z" }
    )
    vod = <<~M3U8
      #EXTM3U
      #EXT-X-PLAYLIST-TYPE:VOD
      #EXT-X-MEDIA-SEQUENCE:1
      #EXT-X-TARGETDURATION:6
      #{(1..8).map { |sequence| "#EXTINF:6,\nsegment-#{sequence}.ts" }.join("\n")}
      #EXT-X-ENDLIST
    M3U8
    capturer = build_capturer(vod)

    first = capturer.call(stream: @stream, state: @state, lease_token: @token, limit: 3)
    assert_equal 3, first.captured_count
    assert_not first.end_list
    assert_equal [ 1, 2, 3 ], @stream.objects.where(kind: "source_segment").order(:sequence).pluck(:sequence)

    second = capturer.call(stream: @stream, state: @state, lease_token: @token, limit: 3)
    assert_equal 3, second.captured_count
    assert_not second.end_list

    final = capturer.call(stream: @stream, state: @state, lease_token: @token, limit: 3)
    assert_equal 2, final.captured_count
    assert final.end_list
    assert_equal (1..8).to_a, @stream.objects.where(kind: "source_segment").order(:sequence).pluck(:sequence)

    object = @stream.objects.find_by!(kind: "source_segment", sequence: 1)
    assert_equal "publication_time_relative_offset", object.metadata.fetch("anchor_source")
    assert_equal "2020-01-02T00:00:00.000000Z", object.metadata.fetch("publication_time_anchor")
    assert_equal 0.0, object.metadata.fetch("relative_start_seconds")
    assert_equal false, object.metadata.fetch("timeline_is_original_broadcast_time")
    assert_not object.metadata.key?("provider_program_date_time")
    recording = @stream.recordings.sole
    assert_equal "finalized", recording.state
    assert_equal false, recording.metadata.fetch("timeline_is_original_broadcast_time")
    assert_equal "2020-01-02T00:00:00.000000Z",
      recording.metadata.fetch("publication_time_anchor")
  end

  test "does not complete on-demand capture until every media track reaches its end" do
    @stream.update!(kind: "on_demand")
    video = <<~M3U8
      #EXTM3U
      #EXT-X-MEDIA-SEQUENCE:1
      #EXT-X-PROGRAM-DATE-TIME:2026-08-17T15:47:08.606Z
      #EXTINF:6,
      video-1.ts
      #EXTINF:6,
      video-2.ts
      #EXT-X-ENDLIST
    M3U8
    audio = <<~M3U8
      #EXTM3U
      #EXT-X-MEDIA-SEQUENCE:1
      #EXT-X-PROGRAM-DATE-TIME:2026-08-17T15:47:08.606Z
      #EXTINF:6,
      audio-1.aac
      #EXTINF:6,
      audio-2.aac
      #EXT-X-ENDLIST
    M3U8
    descriptors = [
      Track.new(track_key: "video:vod", kind: "video", language: "und", role: "main", delivery: "separate",
        parent_track_key: nil, playlist_url: "https://media.example.test/video.m3u8", codec: "avc1", metadata: {}),
      Track.new(track_key: "audio:en", kind: "audio", language: "en", role: "interpreted", delivery: "separate",
        parent_track_key: nil, playlist_url: "https://media.example.test/audio.m3u8", codec: "mp4a", metadata: {})
    ]
    adapter = Struct.new(:descriptors) { def tracks(*) = descriptors }.new(descriptors)
    http = FixtureHttp.new(
      "https://media.example.test/video.m3u8" => video,
      "https://media.example.test/audio.m3u8" => audio
    )
    capturer = Warehouse::Broadcasts::Capturer.new(adapter:, http:, storage: @storage, clock: -> { @now })

    first = capturer.call(stream: @stream, state: @state, lease_token: @token, limit: 3)
    assert_equal 3, first.captured_count
    assert_not first.end_list

    final = capturer.call(stream: @stream, state: @state, lease_token: @token, limit: 3)
    assert_equal 1, final.captured_count
    assert final.end_list
    assert_equal 2, @stream.objects.joins(:media_track).where(kind: "source_segment", "warehouse.media_tracks" => { kind: "audio" }).count
  end

  test "captures a VOD longer than the live backlog and resumes without duplicates" do
    @stream.update!(kind: "on_demand")
    vod = <<~M3U8
      #EXTM3U
      #EXT-X-PLAYLIST-TYPE:VOD
      #EXT-X-MEDIA-SEQUENCE:1
      #EXT-X-TARGETDURATION:2
      #EXT-X-PROGRAM-DATE-TIME:2026-08-17T15:47:08.606Z
      #{(1..30).map { |sequence| "#EXTINF:2,\nsegment-#{sequence}.ts" }.join("\n")}
      #EXT-X-ENDLIST
    M3U8
    capturer = build_capturer(vod)
    results = []

    5.times do
      results << capturer.call(stream: @stream, state: @state, lease_token: @token, limit: 7)
      break if results.last.end_list
    end

    assert_equal [ 7, 7, 7, 7, 2 ], results.map(&:captured_count)
    assert_equal [ false, false, false, false, true ], results.map(&:end_list)
    assert_equal (1..30).to_a,
      @stream.objects.where(kind: "source_segment").order(:sequence).pluck(:sequence)
    assert_equal 30, @stream.objects.where(kind: "source_segment").count
    first_object = @stream.objects.find_by!(kind: "source_segment", sequence: 1)
    assert_equal "program_date_time", first_object.metadata.fetch("anchor_source")
    assert_equal "2026-08-17T15:47:08.606000Z",
      first_object.metadata.fetch("provider_program_date_time")
    assert_not first_object.metadata.key?("timeline_is_original_broadcast_time")
  end

  test "rejects an empty historical ENDLIST instead of completing without a recording" do
    @stream.update!(kind: "on_demand")
    empty_vod = <<~M3U8
      #EXTM3U
      #EXT-X-PLAYLIST-TYPE:VOD
      #EXT-X-ENDLIST
    M3U8

    error = assert_raises(Warehouse::Broadcasts::Hls::UnsupportedTransport) do
      build_capturer(empty_vod).call(stream: @stream, state: @state, lease_token: @token)
    end

    assert_match(/contains no media segments/, error.message)
    assert_empty @stream.recordings
    assert_empty @stream.objects.where(kind: "source_segment")
  end

  test "rejects a historical playlist that is not finalized" do
    @stream.update!(kind: "on_demand")
    unfinished = <<~M3U8
      #EXTM3U
      #EXT-X-MEDIA-SEQUENCE:1
      #EXT-X-PROGRAM-DATE-TIME:2026-08-17T15:47:08.606Z
      #EXTINF:6,
      segment-1.ts
    M3U8

    error = assert_raises(Warehouse::Broadcasts::Hls::UnsupportedTransport) do
      build_capturer(unfinished).call(stream: @stream, state: @state, lease_token: @token)
    end

    assert_match(/archive is not finalized/, error.message)
    assert_empty @stream.objects.where(kind: "source_segment")
  end

  test "marks a stale captured event partial at its last archived byte" do
    capturer = build_capturer(media_fixture)
    capturer.call(stream: @stream, state: @state, lease_token: @token)

    capturer.finalize_stale!(
      stream: @stream, state: @state, lease_token: @token,
      reason: "event_missing_from_discovery_for_600_seconds"
    )

    recording = @stream.recordings.sole
    assert_equal "partial", recording.state
    assert_equal @stream.objects.where(kind: "source_segment").maximum(:ends_at), recording.ends_at
    assert_equal "event_missing_from_discovery_for_600_seconds", recording.metadata.fetch("terminal_reason")
    assert recording.metadata.fetch("capture_complete")
  end

  test "leaves only a deterministic orphan upload when the lease expires before commit" do
    moving_now = @now
    storage = MemoryStorage.new { moving_now += 3.minutes }
    capturer = build_capturer(media_fixture, storage:, clock: -> { moving_now })

    assert_raises(Warehouse::Broadcasts::Capturer::LeaseLost) do
      capturer.call(stream: @stream, state: @state, lease_token: @token, limit: 1)
    end

    assert_equal 1, storage.objects.length
    assert_empty @stream.objects
    assert_equal({}, @state.reload.cursor)
  end

  private

  def build_capturer(media_body, storage: @storage, clock: -> { @now })
    descriptor = Track.new(
      track_key: "video:720p:test", kind: "video", language: "und", role: "main",
      delivery: "separate", parent_track_key: nil,
      playlist_url: "https://media.example.test/video.m3u8", codec: "avc1.4D401F",
      metadata: { "height" => 720 }
    )
    adapter = Struct.new(:descriptors) { def tracks(*) = descriptors }.new([ descriptor ])
    http = FixtureHttp.new("https://media.example.test/video.m3u8" => media_body)
    Warehouse::Broadcasts::Capturer.new(adapter:, http:, storage:, clock:)
  end

  def media_fixture
    Rails.root.join("test/fixtures/files/cpac/media.m3u8").read
  end

  class FixtureHttp
    def initialize(playlists)
      @playlists = playlists
    end

    def get(url, **)
      body = @playlists[url] || "segment bytes for #{url}"
      content_type = @playlists.key?(url) ? "application/vnd.apple.mpegurl" : "video/mp2t"
      Response.new(body:, content_type:, url:, status: 200)
    end
  end

  class MemoryStorage
    attr_reader :objects

    def initialize(&after_upload)
      @objects = {}
      @after_upload = after_upload
    end

    def upload(key:, body:, content_type:)
      @objects[key] = { body:, content_type: }
      @after_upload&.call
    end
  end
end
