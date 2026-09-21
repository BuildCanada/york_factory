require "test_helper"

class Warehouse::Broadcasts::CpacHistoryAdapterTest < ActiveSupport::TestCase
  Response = Warehouse::Broadcasts::HttpClient::Response
  Adapter = Warehouse::Broadcasts::CpacHistoryAdapter
  ID_ONE = "11111111-1111-4111-8111-111111111111"
  ID_TWO = "22222222-2222-4222-8222-222222222222"

  test "lists an inclusive date range with stable pagination and hydrated VOD streams" do
    listing_url = "#{Adapter::SEARCH_URL}?startDate=2026-08-17&endDate=2026-08-18&page=2&order=desc&type=videos"
    routes = {
      listing_url => response("history_search.html", url: listing_url),
      "https://www.cpac.ca/in-committee/episode/committee-one?id=#{ID_ONE}" =>
        response("history_episode_one.html", url: "https://www.cpac.ca/in-committee/episode/committee-one?id=#{ID_ONE}"),
      "https://www.cpac.ca/headline-politics/episode/news-conference?id=#{ID_TWO}" =>
        response("history_episode_two.html", url: "https://www.cpac.ca/headline-politics/episode/news-conference?id=#{ID_TWO}")
    }

    result = Adapter.new(http: fake_http(routes)).list(
      start_date: Date.new(2026, 8, 17), end_date: "2026-08-18", page: 2
    )

    assert_equal 42, result.total
    assert_equal 3, result.next_page
    assert_equal [ "#{ID_ONE}:archive", "#{ID_TWO}:archive" ], result.entries.map(&:external_id)
    assert_empty result.errors
    assert result.entries.all? { |entry| entry.kind == "on_demand" }
    assert_equal "https://cpac-vod.cdn.vustreams.com/cpac/vod/#{ID_ONE}/master.m3u8",
      result.entries.first.manifest_url
    assert_equal result.entries.first.manifest_url,
      result.entries.first.metadata.fetch("historical_manifest_url")
    assert_equal "2026-08-17T00:00:00.000Z",
      result.entries.first.metadata.fetch("provider_published_at")
    assert_nil result.entries.first.scheduled_start_at
    assert_equal ID_ONE, result.entries.first.metadata.fetch("canonical_external_id")
    assert_equal "https://www.cpac.ca/comite/l-episode/comite-un?id=#{ID_ONE}",
      result.entries.first.page_url_fr
  end

  test "find follows the stable episode ID endpoint and retains its canonical response URL" do
    lookup_url = "#{Adapter::EPISODE_URL}?id=#{ID_ONE}"
    canonical_url = "https://www.cpac.ca/in-committee/episode/committee-one?id=#{ID_ONE}"
    adapter = Adapter.new(http: fake_http(
      lookup_url => response("history_episode_one.html", url: canonical_url)
    ))

    stream = adapter.find("#{ID_ONE}:archive")

    assert_equal "#{ID_ONE}:archive", stream.external_id
    assert_equal canonical_url, stream.page_url_en
    assert_equal "Committee One", stream.title_en
    assert_equal "Comité un", stream.title_fr
  end

  test "an empty archive date range is a valid final page" do
    listing_url = "#{Adapter::SEARCH_URL}?startDate=1970-01-01&endDate=1970-01-01&page=1&order=desc&type=videos"
    result = Adapter.new(http: fake_http(
      listing_url => response("history_search_empty.html", url: listing_url)
    )).list(start_date: "1970-01-01", end_date: "1970-01-01")

    assert_equal 0, result.total
    assert_empty result.entries
    assert_empty result.errors
    assert_nil result.next_page
  end

  test "reports a permanently malformed episode without discarding other page entries" do
    listing_url = "#{Adapter::SEARCH_URL}?startDate=2026-08-17&endDate=2026-08-18&page=2&order=desc&type=videos"
    first_url = "https://www.cpac.ca/in-committee/episode/committee-one?id=#{ID_ONE}"
    second_url = "https://www.cpac.ca/headline-politics/episode/news-conference?id=#{ID_TWO}"
    result = Adapter.new(http: fake_http(
      listing_url => response("history_search.html", url: listing_url),
      first_url => response("history_episode_missing_video.html", url: first_url),
      second_url => response("history_episode_two.html", url: second_url)
    )).list(start_date: "2026-08-17", end_date: "2026-08-18", page: 2)

    assert_equal [ "#{ID_TWO}:archive" ], result.entries.map(&:external_id)
    assert_equal ID_ONE, result.errors.first.fetch("external_id")
    assert_match(/omitted video metadata/, result.errors.first.fetch("error"))
  end

  test "delegates VOD master parsing to the verified CPAC track mapping" do
    manifest_url = "https://cpac-vod.cdn.vustreams.com/cpac/vod/#{ID_ONE}/master.m3u8"
    adapter = Adapter.new(http: fake_http(
      manifest_url => response("history_master.m3u8", url: manifest_url, content_type: "application/vnd.apple.mpegurl")
    ))

    tracks = adapter.tracks(manifest_url)

    assert_equal 720, tracks.find { |track| track.kind == "video" }.metadata.fetch("height")
    assert_equal %w[en fr mul], tracks.select { |track| track.kind == "audio" }.map(&:language)
    assert_equal [ [ "en", 1 ], [ "fr", 2 ] ], tracks.select { |track| track.kind == "captions" }
      .map { |track| [ track.language, track.metadata.fetch("caption_field") ] }
  end

  test "rejects inverted ranges and invalid pages before making a request" do
    adapter = Adapter.new(http: fake_http({}))

    assert_raises(ArgumentError) do
      adapter.list(start_date: "2026-08-18", end_date: "2026-08-17")
    end
    assert_raises(ArgumentError) do
      adapter.list(start_date: "2026-08-17", end_date: "2026-08-18", page: 0)
    end
  end

  private

  def response(filename, url:, content_type: "text/html")
    [ filename, content_type, url ]
  end

  def fake_http(routes)
    Class.new do
      define_method(:initialize) { |configured| @routes = configured }
      define_method(:get) do |url, **|
        filename, content_type, response_url = @routes.fetch(url)
        body = Rails.root.join("test/fixtures/files/cpac", filename).read
        Response.new(body:, content_type:, url: response_url, status: 200)
      end
    end.new(routes)
  end
end
