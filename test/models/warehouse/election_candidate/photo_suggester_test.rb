require "test_helper"

class Warehouse::ElectionCandidate::PhotoSuggesterTest < ActiveSupport::TestCase
  FakeResponse = Struct.new(:status, :body)

  class FakeHttp
    def initialize(responses_by_url_fragment)
      @responses = responses_by_url_fragment
    end

    def get(url, **)
      _fragment, response = @responses.find { |fragment, _| url.include?(fragment) }
      response || FakeResponse.new(404, "")
    end
  end

  setup do
    suffix = SecureRandom.hex(4)
    toronto = Warehouse::Jurisdiction.find_or_create_by!(slug: "toronto") do |j|
      j.name = "City of Toronto"
      j.code = "TOR-ON"
      j.level = "municipal"
      j.fiscal_year_start_month = 1
      j.default_currency = "CAD"
    end
    election = Warehouse::Election.find_or_create_by!(slug: "toronto-2026") do |e|
      e.jurisdiction = toronto
      e.name = "Toronto 2026 General Municipal Election"
      e.kind = "municipal"
      e.election_date = Date.new(2026, 10, 26)
    end
    race = election.races.find_or_create_by!(office_type: "mayor", district_type: "at_large")
    @candidate = race.candidates.create!(
      full_name: "Chow, Olivia #{suffix}",
      first_name: "Olivia",
      last_name: "Chow #{suffix}",
      status: "active",
      website: "https://oliviachow.ca"
    )
  end

  def wikipedia_summary(type: "standard", image: "https://upload.wikimedia.org/olivia.jpg")
    JSON.generate(
      "type" => type,
      "description" => "Canadian politician",
      "originalimage" => image ? { "source" => image } : nil,
      "content_urls" => { "desktop" => { "page" => "https://en.wikipedia.org/wiki/Olivia_Chow" } }
    )
  end

  test "collects wikipedia and campaign-site suggestions" do
    http = FakeHttp.new(
      "en.wikipedia.org" => FakeResponse.new(200, wikipedia_summary),
      "oliviachow.ca" => FakeResponse.new(200, '<html><head><meta property="og:image" content="/images/portrait.jpg"></head></html>')
    )

    suggestions = @candidate.photo_suggester.suggest(http: http)

    assert_equal %w[wikipedia campaign_site], suggestions.map { |s| s["source"] }
    assert_equal "https://upload.wikimedia.org/olivia.jpg", suggestions.first["image_url"]
    assert_equal "Canadian politician", suggestions.first["note"]
    # Relative og:image URLs resolve against the site.
    assert_equal "https://oliviachow.ca/images/portrait.jpg", suggestions.last["image_url"]
    assert_equal 2, @candidate.reload.photo_suggestions.size
  end

  test "skips wikipedia disambiguation pages" do
    http = FakeHttp.new(
      "en.wikipedia.org" => FakeResponse.new(200, wikipedia_summary(type: "disambiguation"))
    )

    suggestions = @candidate.photo_suggester.suggest(http: http)

    refute suggestions.any? { |s| s["source"] == "wikipedia" }
  end

  test "skips wikipedia pages without an image and sites without og:image" do
    http = FakeHttp.new(
      "en.wikipedia.org" => FakeResponse.new(200, wikipedia_summary(image: nil)),
      "oliviachow.ca" => FakeResponse.new(200, "<html><head><title>hi</title></head></html>")
    )

    assert_equal [], @candidate.photo_suggester.suggest(http: http)
    assert_equal [], @candidate.reload.photo_suggestions
  end

  test "tolerates source failures without raising" do
    http = Object.new
    def http.get(*, **) = raise "connection refused"

    assert_equal [], @candidate.photo_suggester.suggest(http: http)
  end

  test "skips the website lookup when no website is on file" do
    @candidate.update!(website: nil)
    http = FakeHttp.new("en.wikipedia.org" => FakeResponse.new(200, wikipedia_summary))

    suggestions = @candidate.photo_suggester.suggest(http: http)

    assert_equal %w[wikipedia], suggestions.map { |s| s["source"] }
  end
end
