require "test_helper"

class Warehouse::Source::Fetcher::SshrcAwardsTest < ActiveSupport::TestCase
  FakeResponse = Data.define(:status, :body) do
    def each
      body.bytes.each_slice(31) { |bytes| yield bytes.pack("C*") }
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

  SOURCE_URL = Warehouse::Source::Fetcher::SshrcAwards::CATALOGUE_URL
  YEAR_1998_URL = "http://www.sshrc-crsh.gc.ca/opendata/SSHRC_FYR1998_AWARD.csv".freeze
  YEAR_1998_REQUEST_URL = YEAR_1998_URL.sub("http://", "https://").freeze
  YEAR_2015_URL = "https://www.sshrc-crsh.gc.ca/opendata/Open Data_FY 2015-16 Expenditures Revised.csv".freeze
  YEAR_2024_URL = "https://www.sshrc-crsh.gc.ca/opendata/SSHRC_FY2024_Expenditures.csv".freeze

  test "downloads payment resources and normalizes historical and current headers" do
    historical = csv(
      "cle,Name-Nom,role,AwardAmount,FiscalYear-Exercice financier,Institution,Établissement,Province_ID,ProvinceEN,ProvinceFR,Competition_Year,Title,Keywords,ProgramNameEN,ProgramNameFR,DisciplineEN,DisciplineFR,MainDisciplineEN,MainDisciplineFR,Area_of_ResearchEN,Area_of_ResearchFR",
      '1,"Fogarassy, José",Applicant,1399.00,1998,McGill University,Université McGill,QC,Quebec,Québec,1997,Technology transfer,innovation,Master Scholarships,Bourses de maîtrise,Law,Droit,Law,Droit,Economic Development,Développement économique'
    ).encode(Encoding::Windows_1252)
    current = "\uFEFF" + csv(
      "cle,File_Number,Name-Nom,Role-Rôle,Amount-Montant,Fiscal_Year-Exercice_financier,Institution,Établissement,Province_ID,Province_EN,Province_FR,Competition_Year-Année_du_concours,Title-Titre,Keywords-Mots-clés,Program,Programme,SSHRC_Discipline_EN,CRSH_Discipline_FR,SSHRC_Main_Discipline,CRSH_Discipline_principale,SSHRC_Area_of_Research,CRSH_Domaine_de_recherche",
      '20997312,1003-2024-0099,"McDonough, Kevin M.",Applicant,22500.0,2024,McGill University,Université McGill,QC,Quebec,Québec,2024,Political Challenges,Polarization,Connection Grant,Subvention Connexion,Civic Education,Éducation civique,Education,Éducation,Education,Éducation'
    )
    http = fake_http(
      resources: [
        resource("2024 Payments", YEAR_2024_URL),
        resource("2024 Partners", "https://example.test/partners.csv"),
        resource("1998 payments", YEAR_1998_URL)
      ],
      downloads: { YEAR_1998_REQUEST_URL => historical, YEAR_2024_URL => current }
    )

    downloads = fetched_downloads(http)
    rows = downloads.flat_map { |download| download.fetch(:rows) }

    assert_equal [ 1998, 2024 ], downloads.pluck(:year)
    assert_equal %w[1 20997312], rows.pluck("external_id")
    assert_equal "Fogarassy, José", rows.first.fetch("recipient_name")
    assert_equal "Master Scholarships", rows.first.fetch("program")
    assert_equal "1003-2024-0099", rows.last.fetch("application_id")
    assert_equal "Civic Education", rows.last.fetch("discipline")
    assert_equal "Education", rows.last.fetch("main_discipline")
    assert_equal "http://www.outil.ost.uqam.ca/CRSH/Detail.aspx?Cle=20997312&Langue=2", rows.last.fetch("source_url")
    assert_equal YEAR_2024_URL, JSON.parse(rows.last.fetch("source_fields")).fetch("_resource_url")
    assert_equal [
      { url: SOURCE_URL },
      { url: YEAR_1998_REQUEST_URL, stream: true },
      { url: YEAR_2024_URL, stream: true }
    ], http.requests
  end

  test "filters years and escapes literal spaces in resource URLs" do
    http = fake_http(
      resources: [ resource("2015 Payments", YEAR_2015_URL), resource("2024 Payments", YEAR_2024_URL) ],
      downloads: {
        YEAR_2015_URL.gsub(" ", "%20") => csv(
          "Cle,Name-Nom,Role, AwardAmount ,FiscalYear-Exercice financier,Institution,ProvinceEN,Competition_Year,Title,ProgramNameEN",
          "65506,Canada Centre,Institution-Based Application,302000,2015,Canada Centre,Ontario,2013,Mining Network,Business-Led Networks"
        )
      }
    )

    downloads = fetched_downloads(http, years: [ 2015 ])

    assert_equal [ 2015 ], downloads.pluck(:year)
    assert_equal "65506", downloads.sole.fetch(:rows).sole.fetch("external_id")
    assert_equal "http://www.outil.ost.uqam.ca/CRSH/Detail.aspx?Cle=65506&Langue=2",
      downloads.sole.fetch(:rows).sole.fetch("source_url")
    assert_equal YEAR_2015_URL.gsub(" ", "%20"), http.requests.last.fetch(:url)
  end

  test "rejects missing and malformed award ids" do
    [
      [ ",Applicant,100", /invalid award id/ ],
      [ "not-numeric,Applicant,100", /invalid award id/ ]
    ].each do |rows, message|
      http = fake_http(
        resources: [ resource("2024 Payments", YEAR_2024_URL) ],
        downloads: { YEAR_2024_URL => csv("cle,Role,Amount-Montant", *rows.split("\r\n")) }
      )

      error = assert_raises(RuntimeError) { fetched_downloads(http) }
      assert_match message, error.message
    end
  end

  test "creates stable distinct external ids for repeated award ids" do
    body = csv(
      "cle,Name-Nom,Role,Amount-Montant,Institution,Fiscal_Year-Exercice_financier",
      "35,Norris,Applicant,20000,Memorial University,1998",
      "35,Norris,Applicant,20000,University of Alberta,1998",
      "35,Norris,Applicant,20000,University of Alberta,1998"
    )
    http = fake_http(
      resources: [ resource("1998 Payments", YEAR_1998_URL) ],
      downloads: { YEAR_1998_REQUEST_URL => body }
    )

    rows = fetched_downloads(http).sole.fetch(:rows)

    assert_equal 3, rows.pluck("external_id").uniq.size
    assert rows.all? { |row| row.fetch("external_id").start_with?("35-") }
    assert rows.last.fetch("external_id").end_with?("-2")
    assert rows.all? { |row| row.fetch("source_url").include?("Cle=35&") }

    second_http = fake_http(
      resources: [ resource("1998 Payments", YEAR_1998_URL) ],
      downloads: { YEAR_1998_REQUEST_URL => body }
    )
    assert_equal rows.pluck("external_id"), fetched_downloads(second_http).sole.fetch(:rows).pluck("external_id")
  end

  test "yields a completed year before a later download fails" do
    http = fake_http(
      resources: [ resource("1998 Payments", YEAR_1998_URL), resource("2024 Payments", YEAR_2024_URL) ],
      downloads: {
        YEAR_1998_REQUEST_URL => csv("cle,FiscalYear-Exercice financier", "1,1998"),
        YEAR_2024_URL => FakeResponse.new(503, "unavailable")
      }
    )
    completed = []

    error = assert_raises(RuntimeError) do
      Warehouse::Source::Fetcher::SshrcAwards.new(SOURCE_URL, http: http).each_year do |download|
        completed << download.year
        download.io.close!
      end
    end

    assert_equal [ 1998 ], completed
    assert_match(/HTTP 503/, error.message)
  end

  test "rejects a catalogue without yearly payment CSVs" do
    http = fake_http(resources: [ resource("Table Definition", YEAR_1998_URL) ])

    error = assert_raises(RuntimeError) do
      Warehouse::Source::Fetcher::SshrcAwards.new(SOURCE_URL, http: http).each_year.to_a
    end

    assert_match(/no yearly payment CSVs/, error.message)
  end

  private

  def fetched_downloads(http, years: nil)
    [].tap do |downloads|
      Warehouse::Source::Fetcher::SshrcAwards.new(SOURCE_URL, http: http, years: years).each_year do |download|
        downloads << {
          year: download.year,
          checksum: download.checksum,
          rows: CSV.new(download.io, headers: true).map(&:to_h)
        }
        download.io.close!
      end
    end
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
