require "test_helper"

class Warehouse::Broadcasts::HlsTest < ActiveSupport::TestCase
  test "parses master variants and quoted rendition attributes" do
    playlist = Warehouse::Broadcasts::Hls.parse(fixture("master.m3u8"), base_url: "https://media.example.test/live/master.m3u8")

    assert_instance_of Warehouse::Broadcasts::Hls::Master, playlist
    assert_equal [ 360, 720, 1080 ], playlist.variants.map(&:height)
    assert_equal "https://media.example.test/live/audio-en.m3u8", playlist.renditions.first.uri
    assert_equal "CC1", playlist.renditions.last.instream_id
  end

  test "preserves provider time, discontinuities, and sequence numbers" do
    playlist = Warehouse::Broadcasts::Hls.parse(fixture("media.m3u8"), base_url: "https://media.example.test/live/video.m3u8")

    assert_equal 100, playlist.media_sequence
    assert_equal [ 100, 101, 102 ], playlist.segments.map(&:sequence)
    assert_equal "program_date_time", playlist.segments.first.anchor_source
    assert_equal "program_date_time_derived", playlist.segments.second.anchor_source
    assert_in_delta Time.iso8601("2026-09-21T14:55:37.546133Z"), playlist.segments.second.starts_at, 0.000001
    assert playlist.segments.last.discontinuity
    assert_equal 5, playlist.segments.last.discontinuity_sequence
    assert_equal Time.iso8601("2026-09-21T15:00:00Z"), playlist.segments.last.starts_at
  end

  test "rejects media with no provider timeline anchor" do
    error = assert_raises(Warehouse::Broadcasts::Hls::ParseError) do
      Warehouse::Broadcasts::Hls.parse("#EXTM3U\n#EXTINF:6,\nsegment.ts\n", base_url: "https://media.example.test/live.m3u8")
    end

    assert_match(/no provider timeline anchor/, error.message)
  end

  test "uses a publication anchor with explicit relative offsets when VOD has no media UTC" do
    playlist = Warehouse::Broadcasts::Hls.parse(
      <<~M3U8,
        #EXTM3U
        #EXT-X-PLAYLIST-TYPE:VOD
        #EXT-X-MEDIA-SEQUENCE:7
        #EXTINF:5.5,
        first.ts
        #EXT-X-DISCONTINUITY
        #EXTINF:4,
        second.ts
        #EXT-X-ENDLIST
      M3U8
      base_url: "https://media.example.test/vod/video.m3u8",
      timeline_anchor: Time.iso8601("2020-01-02T00:00:00Z")
    )

    assert_equal [ "publication_time_relative_offset" ] * 2, playlist.segments.map(&:anchor_source)
    assert_equal [ 0.0, 5.5 ], playlist.segments.map(&:relative_start)
    assert_equal Time.iso8601("2020-01-02T00:00:05.5Z"), playlist.segments.second.starts_at
    assert playlist.end_list
  end

  test "does not apply a publication anchor to a playlist that is not finite" do
    error = assert_raises(Warehouse::Broadcasts::Hls::ParseError) do
      Warehouse::Broadcasts::Hls.parse(
        "#EXTM3U\n#EXTINF:6,\nsegment.ts\n",
        base_url: "https://media.example.test/live.m3u8",
        timeline_anchor: Time.iso8601("2020-01-02T00:00:00Z")
      )
    end

    assert_match(/finite VOD playlist/, error.message)
  end

  test "rejects encrypted playlists and non-positive durations" do
    encrypted = "#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI=\"key.bin\"\n#EXT-X-PROGRAM-DATE-TIME:2026-09-21T00:00:00Z\n#EXTINF:6,\nsegment.ts\n"
    assert_raises(Warehouse::Broadcasts::Hls::ParseError) do
      Warehouse::Broadcasts::Hls.parse(encrypted, base_url: "https://media.example.test/live.m3u8")
    end

    malformed = "#EXTM3U\n#EXT-X-PROGRAM-DATE-TIME:2026-09-21T00:00:00Z\n#EXTINF:0,\nsegment.ts\n"
    assert_raises(Warehouse::Broadcasts::Hls::ParseError) do
      Warehouse::Broadcasts::Hls.parse(malformed, base_url: "https://media.example.test/live.m3u8")
    end
  end

  test "normalizes implicit byte ranges and rejects fragmented MP4 init maps" do
    ranged = <<~M3U8
      #EXTM3U
      #EXT-X-PROGRAM-DATE-TIME:2026-09-21T00:00:00Z
      #EXT-X-BYTERANGE:100@20
      #EXTINF:6,
      media.ts
      #EXT-X-BYTERANGE:50
      #EXTINF:6,
      media.ts
    M3U8
    playlist = Warehouse::Broadcasts::Hls.parse(ranged, base_url: "https://media.example.test/live.m3u8")
    assert_equal({ "length" => 50, "offset" => 120 }, playlist.segments.second.byte_range)

    unsupported = "#EXTM3U\n#EXT-X-MAP:URI=\"init.mp4\"\n"
    assert_raises(Warehouse::Broadcasts::Hls::ParseError) do
      Warehouse::Broadcasts::Hls.parse(unsupported, base_url: "https://media.example.test/live.m3u8")
    end
  end

  private

  def fixture(name)
    Rails.root.join("test/fixtures/files/cpac", name).read
  end
end
