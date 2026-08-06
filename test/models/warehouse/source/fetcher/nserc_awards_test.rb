require "test_helper"

class Warehouse::Source::Fetcher::NsercAwardsTest < ActiveSupport::TestCase
  FakeResponse = Data.define(:status, :body) do
    def each
      yield body
    end
  end

  class FakeHttp
    attr_reader :requests

    def initialize(responses)
      @responses = responses
      @requests = []
    end

    def get(url, **options)
      @requests << { url: url, **options }
      @responses.fetch(url) { raise "unexpected request: #{url}" }
    end
  end

  SOURCE_URL = "https://open.canada.ca/data/api/action/package_show?id=nserc".freeze
  YEAR_1991_URL = "https://www.nserc-crsng.gc.ca/opendata/NSERC_FY1991_Expenditures.csv".freeze
  YEAR_2024_URL = "https://www.nserc-crsng.gc.ca/opendata/NSERC_FY2024_Expenditures.csv".freeze

  test "downloads advertised yearly award CSVs and normalizes historical header variants" do
    http = fake_http(
      resources: [
        resource("2024 Awards", YEAR_2024_URL),
        resource("2024 Partners", "https://example.test/partners.csv"),
        resource("1991 Awards", YEAR_1991_URL)
      ],
      downloads: {
        YEAR_1991_URL => csv(
          "ApplicationID,Name-Nom,Institution-Établissement,FiscalYear-Exercice-financier,AwardAmount,ProgramNaneEN,ApplicationTitle,ApplicationSummary,ProvinceEN,CountryEN",
          "116033-1991,Researcher One,University One,1991,8552,Fellowships,Old title,Old summary,Ontario,CANADA"
        ),
        YEAR_2024_URL => csv(
          "ApplicationID,Name-Nom,Institution-Établissement,FiscalYear-Exercice financier,AwardAmount,ProgramNameEN,ProgramID,ApplicationTitle,ApplicationSummary,ProvinceEN,CountryEN",
          "305407-2017,Researcher Two,University Two,2024,24000,Northern Supplement,RGPNS,New title,New summary,Quebec,CANADA"
        )
      }
    )

    downloads = fetched_downloads(http)
    rows = downloads.flat_map { |download| download.fetch(:rows) }

    assert_equal [ 1991, 2024 ], downloads.pluck(:year)
    assert_equal 2, rows.size
    assert_equal [ "116033-1991-1991", "305407-2017-2024" ], rows.pluck("external_id")
    assert_equal [
      { url: SOURCE_URL },
      { url: YEAR_1991_URL, stream: true },
      { url: YEAR_2024_URL, stream: true }
    ], http.requests

    current = rows.last
    assert_equal "Researcher Two", current.fetch("recipient_name")
    assert_equal "University Two", current.fetch("recipient_organization")
    assert_equal "Northern Supplement", current.fetch("program")
    assert_equal "RGPNS", current.fetch("program_id")
    assert_equal YEAR_2024_URL, current.fetch("source_url")
  end

  test "creates deterministic distinct ids for unidentified rows" do
    unidentified = "NA,Batch report,NSERC,2010,157840,Parental Leave,Batch title,Summary,Ontario,CANADA"
    http = fake_http(
      resources: [ resource("2010 Awards", YEAR_1991_URL) ],
      downloads: {
        YEAR_1991_URL => csv(
          "ApplicationID,Name-Nom,Institution-Établissement,FiscalYear-Exercice financier,AwardAmount,ProgramNameEN,ApplicationTitle,ApplicationSummary,ProvinceEN,CountryEN",
          unidentified,
          unidentified
        )
      }
    )

    rows = fetched_downloads(http).sole.fetch(:rows)

    assert_equal 2, rows.size
    assert_equal 2, rows.pluck("external_id").uniq.size
    assert rows.all? { |row| row.fetch("external_id").start_with?("unidentified-2010-") }
  end

  test "preserves distinct payments that share an application and fiscal year" do
    http = fake_http(
      resources: [ resource("2024 Awards", YEAR_2024_URL) ],
      downloads: {
        YEAR_2024_URL => csv(
          "ApplicationID,Name-Nom,OrganizationID,Institution-Établissement,FiscalYear-Exercice financier,AwardAmount,ProgramID",
          "566475-2021,Researcher,6142,Fisheries and Oceans Canada,2024,15517.97,ALLRP",
          "566475-2021,Researcher,2,The University of British Columbia,2024,76802.03,ALLRP"
        )
      }
    )

    rows = fetched_downloads(http).sole.fetch(:rows)

    assert_equal 2, rows.size
    assert_equal 2, rows.pluck("external_id").uniq.size
    assert rows.all? { |row| row.fetch("external_id").start_with?("566475-2021-2024-") }
  end

  test "preserves exact duplicate official rows with deterministic ordinal ids" do
    duplicate = "566475-2021,Researcher,2,University,2024,76802.03,ALLRP"
    http = fake_http(
      resources: [ resource("2024 Awards", YEAR_2024_URL) ],
      downloads: {
        YEAR_2024_URL => csv(
          "ApplicationID,Name-Nom,OrganizationID,Institution-Établissement,FiscalYear-Exercice financier,AwardAmount,ProgramID",
          duplicate,
          duplicate
        )
      }
    )

    first_ids = fetched_downloads(http).sole.fetch(:rows).pluck("external_id")
    second_ids = fetched_downloads(fake_http(
      resources: [ resource("2024 Awards", YEAR_2024_URL) ],
      downloads: { YEAR_2024_URL => csv(
        "ApplicationID,Name-Nom,OrganizationID,Institution-Établissement,FiscalYear-Exercice financier,AwardAmount,ProgramID",
        duplicate,
        duplicate
      ) }
    )).sole.fetch(:rows).pluck("external_id")

    assert_equal 2, first_ids.uniq.size
    assert_equal first_ids, second_ids
    assert_match(/-2\z/, first_ids.last)
  end

  test "rejects a catalogue without yearly award CSVs" do
    http = fake_http(resources: [ resource("Table definition - Awards", YEAR_1991_URL) ])

    error = assert_raises(RuntimeError) do
      Warehouse::Source::Fetcher::NsercAwards.new(SOURCE_URL, http: http).each_year.to_a
    end

    assert_match(/no yearly award CSVs/, error.message)
  end

  test "rejects failed yearly downloads" do
    http = fake_http(
      resources: [ resource("2024 Awards", YEAR_2024_URL) ],
      downloads: { YEAR_2024_URL => FakeResponse.new(503, "unavailable") }
    )

    error = assert_raises(RuntimeError) do
      Warehouse::Source::Fetcher::NsercAwards.new(SOURCE_URL, http: http).each_year.to_a
    end

    assert_match(/HTTP 503/, error.message)
  end

  test "yields completed years before a later year fails" do
    http = fake_http(
      resources: [ resource("1991 Awards", YEAR_1991_URL), resource("2024 Awards", YEAR_2024_URL) ],
      downloads: {
        YEAR_1991_URL => csv(
          "ApplicationID,Name-Nom,FiscalYear-Exercice financier,AwardAmount",
          "116033-1991,Researcher One,1991,8552"
        ),
        YEAR_2024_URL => FakeResponse.new(503, "unavailable")
      }
    )
    completed = []

    error = assert_raises(RuntimeError) do
      Warehouse::Source::Fetcher::NsercAwards.new(SOURCE_URL, http: http).each_year do |download|
        completed << download.year
        download.io.close!
      end
    end

    assert_equal [ 1991 ], completed
    assert_match(/HTTP 503/, error.message)
  end

  private

  def fetched_downloads(http)
    downloads = []
    Warehouse::Source::Fetcher::NsercAwards.new(SOURCE_URL, http: http).each_year do |download|
      downloads << {
        year: download.year,
        checksum: download.checksum,
        rows: CSV.new(download.io, headers: true).map(&:to_h)
      }
      download.io.close!
    end
    downloads
  end

  def fake_http(resources:, downloads: {})
    catalogue = JSON.generate("success" => true, "result" => { "resources" => resources })
    FakeHttp.new({ SOURCE_URL => FakeResponse.new(200, catalogue) }.merge(downloads.transform_values { |value|
      value.is_a?(FakeResponse) ? value : FakeResponse.new(200, value)
    }))
  end

  def resource(name, url)
    { "name" => name, "format" => "CSV", "url" => url }
  end

  def csv(header, *rows)
    ([ header ] + rows).join("\r\n")
  end
end
