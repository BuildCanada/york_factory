require "test_helper"

class Warehouse::Spending::Scrapers::SshrcAwardsTest < ActiveSupport::TestCase
  test "normalizes a legacy detail page" do
    payload = <<~HTML
      <!doctype html>
      <html>
        <body>
          <a href="Detail.aspx?Cle=98765&amp;Langue=2">Permalink</a>
          <span id="InfoTitre">Community archives</span>
          <span id="InfoProgramme">Insight Grant</span>
          <span id="InfoFiscal">2022</span>
          <span id="InfoCompetition">2022-2023</span>
          <span id="InfoChercheur">Doe, Jane</span>
          <span id="InfoOrganisation">University of Alberta, Alberta</span>
          <span id="InfoMontant">$125,000</span>
          <span id="InfoDiscipline">History</span>
          <span id="InfoSujet">Archives</span>
          <span id="InfoCoChercheur">Smith, Alex</span>
          <span id="InfoKeywords">archives; communities</span>
        </body>
      </html>
    HTML

    attributes = parsed_attributes(payload).sole

    assert_equal "98765", attributes[:external_key]
    assert_equal "Community archives", attributes[:title]
    assert_equal "Doe, Jane", attributes[:recipient_name]
    assert_equal "individual", attributes[:recipient_type]
    assert_equal "Insight Grant", attributes[:program_name]
    assert_equal 2022, attributes[:fiscal_year]
    assert_equal BigDecimal("125000"), attributes[:amount]
    assert_equal "AB", attributes[:province_code]
    assert_equal "CA", attributes[:country_code]
    assert_equal "History", attributes.dig(:metadata, "discipline")
    assert_includes attributes[:source_url], "Cle=98765"
  end

  test "normalizes archived JSON records" do
    payload = [
      {
        id: "A-42",
        title: "Digital citizenship",
        program: "Connection Grant",
        fiscal_year: "2023-2024",
        competition_year: "2023",
        applicant: "Lee, Morgan",
        organization: "Université Laval, Québec",
        amount: "75,500.25",
        discipline: "Communication",
        area_of_research: "Digital media",
        keywords: [ "citizenship", "media" ],
        source_url: "https://example.test/awards/A-42"
      }
    ].to_json

    attributes = parsed_attributes(payload).sole

    assert_equal "A-42", attributes[:external_key]
    assert_equal "Digital citizenship", attributes[:title]
    assert_equal "Lee, Morgan", attributes[:recipient_name]
    assert_equal "Connection Grant", attributes[:program_name]
    assert_equal 2023, attributes[:fiscal_year]
    assert_equal BigDecimal("75500.25"), attributes[:amount]
    assert_equal "QC", attributes[:province_code]
    assert_equal "CA", attributes[:country_code]
    assert_equal "citizenship; media", attributes.dig(:metadata, "keywords")
    assert_equal "https://example.test/awards/A-42", attributes[:source_url]
  end

  test "normalizes canonical payment CSVs" do
    payload = StringIO.new(<<~CSV)
      external_id,application_id,recipient_name,recipient_organization,recipient_role,title,description,award_amount,fiscal_year,competition_year,program,discipline,main_discipline,area_of_research,keywords,province,country,source_url,source_fields
      20997312,1003-2024-0099,"McDonough, Kevin M.",McGill University,Applicant,Political Challenges,,22500.0,2024,2024,Connection Grant,Civic Education,Education,Education,Polarization,Quebec,Canada,https://example.test/2024.csv,"{""cle"":""20997312""}"
    CSV

    attributes = parsed_attributes(payload).sole

    assert_equal "20997312", attributes[:external_key]
    assert_equal "McDonough, Kevin M.", attributes[:recipient_name]
    assert_equal "individual", attributes[:recipient_type]
    assert_equal BigDecimal("22500"), attributes[:amount]
    assert_equal "QC", attributes[:province_code]
    assert_equal "CA", attributes[:country_code]
    assert_equal "1003-2024-0099", attributes.dig(:metadata, "application_id")
    assert_equal "Education", attributes.dig(:metadata, "main_discipline")
    assert_equal({ "cle" => "20997312" }, attributes.dig(:metadata, "source_fields"))
  end

  test "classifies institution-based canonical recipients as organizations" do
    payload = <<~CSV
      external_id,recipient_name,recipient_organization,recipient_role,title,award_amount,fiscal_year,program,province,country
      65506,Canada Centre,Canada Centre,Institution-Based Application,Mining Network,302000,2015,Business-Led Networks,Ontario,Canada
    CSV

    attributes = parsed_attributes(payload).sole

    assert_equal "organization", attributes[:recipient_type]
    assert_equal "Canada Centre", attributes[:recipient_name]
  end

  private

  def parsed_attributes(payload)
    source = Struct.new(:url).new("http://www.outil.ost.uqam.ca/CRSH/Resultat.aspx")
    ingestion = Struct.new(:source).new(source)
    [].tap do |attributes|
      Warehouse::Spending::Scrapers::SshrcAwards.new(ingestion).send(:each_attributes, payload) do |value|
        attributes << value
      end
    end
  end
end
