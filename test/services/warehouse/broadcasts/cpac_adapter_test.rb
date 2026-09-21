require "test_helper"

class Warehouse::Broadcasts::CpacAdapterTest < ActiveSupport::TestCase
  Response = Warehouse::Broadcasts::HttpClient::Response

  test "discovers TV and simultaneous public events without using the stale TV date" do
    adapter = Warehouse::Broadcasts::CpacAdapter.new(http: fake_http(
      Warehouse::Broadcasts::CpacAdapter::LISTING_URL => [ "live.json", "application/json" ]
    ))

    streams = adapter.discover

    assert_equal [ "tv-feed", "event-one" ], streams.map(&:external_id)
    assert_equal [ "continuous", "event" ], streams.map(&:kind)
    assert_nil streams.first.scheduled_start_at
    assert_equal Time.iso8601("2026-09-21T15:19:57Z"), streams.second.scheduled_start_at
    assert_equal "https://www.cpac.ca/event?id=event-one", streams.second.page_url_en
  end

  test "selects one 720p video, all CPAC audio, and explicit caption fields" do
    manifest_url = "https://media.example.test/event/master.m3u8"
    adapter = Warehouse::Broadcasts::CpacAdapter.new(http: fake_http(
      manifest_url => [ "master.m3u8", "application/vnd.apple.mpegurl" ]
    ))

    tracks = adapter.tracks(manifest_url)

    video = tracks.find { |track| track.kind == "video" }
    assert_equal "https://media.example.test/event/video-720.m3u8", video.playlist_url
    assert_equal 720, video.metadata.fetch("height")
    assert_equal %w[en fr mul], tracks.select { |track| track.kind == "audio" }.map(&:language)
    captions = tracks.select { |track| track.kind == "captions" }
    assert_equal [ [ "en", 1 ], [ "fr", 2 ] ], captions.map { |track| [ track.language, track.metadata.fetch("caption_field") ] }
    assert captions.all? { |track| track.parent_track_key == video.track_key }
    assert captions.all? { |track| track.metadata.fetch("mapping_evidence").include?("parliamentary sample") }
  end

  test "audio track keys remain stable when renditions reorder" do
    manifest_url = "https://media.example.test/event/master.m3u8"
    original = Rails.root.join("test/fixtures/files/cpac/master.m3u8").read
    lines = original.lines
    audio_indexes = lines.each_index.select { |index| lines[index].start_with?("#EXT-X-MEDIA:TYPE=AUDIO") }
    reordered = lines.dup
    reordered.values_at(*audio_indexes).reverse.each_with_index { |line, index| reordered[audio_indexes[index]] = line }

    first = adapter_for_body(manifest_url, original).tracks(manifest_url)
    second = adapter_for_body(manifest_url, reordered.join).tracks(manifest_url)
    assert_equal first.select { |track| track.kind == "audio" }.map(&:track_key).sort,
      second.select { |track| track.kind == "audio" }.map(&:track_key).sort
  end

  test "fails visibly when no video rendition meets the ceiling" do
    manifest_url = "https://media.example.test/event/master.m3u8"
    body = Rails.root.join("test/fixtures/files/cpac/master.m3u8").read
      .gsub(/RESOLUTION=\d+x(?:360|720)/, "RESOLUTION=1920x1080")

    assert_raises(Warehouse::Broadcasts::Hls::ParseError) do
      adapter_for_body(manifest_url, body).tracks(manifest_url)
    end
  end

  private

  def fake_http(routes)
    Class.new do
      define_method(:initialize) { |configured| @routes = configured }
      define_method(:get) do |url, **|
        filename, content_type = @routes.fetch(url)
        body = Rails.root.join("test/fixtures/files/cpac", filename).read
        Response.new(body:, content_type:, url:, status: 200)
      end
    end.new(routes)
  end

  def adapter_for_body(url, body)
    http = Struct.new(:url, :body) do
      def get(requested, **)
        raise "unexpected URL" unless requested == url

        Response.new(body:, content_type: "application/vnd.apple.mpegurl", url:, status: 200)
      end
    end.new(url, body)
    Warehouse::Broadcasts::CpacAdapter.new(http:)
  end
end
