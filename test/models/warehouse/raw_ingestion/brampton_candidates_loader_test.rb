require "test_helper"

class Warehouse::RawIngestion::BramptonCandidatesLoaderTest < ActiveSupport::TestCase
  setup do
    suffix = SecureRandom.hex(4)

    brampton = Warehouse::Jurisdiction.find_or_create_by!(slug: "brampton") do |j|
      j.name = "City of Brampton"
      j.code = "BRM-ON"
      j.level = "municipal"
      j.fiscal_year_start_month = 1
      j.default_currency = "CAD"
    end
    @election = Warehouse::Election.find_or_create_by!(slug: "brampton-2026") do |e|
      e.jurisdiction = brampton
      e.name = "Brampton 2026 General Municipal Election"
      e.kind = "municipal"
      e.election_date = Date.new(2026, 10, 26)
      e.nomination_close_date = Date.new(2026, 8, 21)
    end

    source = Warehouse::Source.create!(
      name: "election_brampton_test_#{suffix}_2026",
      url: "https://www.brampton.ca/EN/City-Hall/Election/Candidates/Pages/candidateListing.aspx",
      format: "brampton_candidates_html"
    )
    @raw_ingestion = source.raw_ingestions.create!(
      fetched_at: Time.current,
      raw_file_path: "raw/test/#{suffix}.json",
      checksum: SecureRandom.hex(32),
      status: :pending
    )
  end

  def body(year: "2026", offices: [])
    JSON.generate("year" => year, "offices" => offices)
  end

  def office(code:, heading:, wards:, candidates: [])
    { "code" => code, "heading" => heading, "wards" => wards, "candidates" => candidates }
  end

  def candidate(name:, date: "05082026", date_text: "5/8/2026", withdrawn: false, cell_phone: nil,
                campaign_phone: nil, email: nil, website: nil, socials: [])
    {
      "name" => name, "filing_date" => date, "filing_date_text" => date_text, "withdrawn" => withdrawn,
      "cell_phone" => cell_phone, "campaign_phone" => campaign_phone, "email" => email,
      "website" => website, "socials" => socials
    }
  end

  test "creates races and candidates for mayor, councillor districts, and trustee boards" do
    payload = body(offices: [
      office(code: "mayor", heading: "Mayor", wards: (1..10).to_a, candidates: [
        candidate(name: "Dhaliwal, Avi", date: "05042026", date_text: "5/4/2026",
          cell_phone: "416.882.1200", email: "elect@avidhaliwal.com", website: "http://www.avidhaliwal.com",
          socials: [ { "name" => "web", "url" => "http://www.avidhaliwal.com" },
                     { "name" => "instagram", "url" => "http://instagram.com/avi.s.dhaliwal" } ])
      ]),
      office(code: "cc15", heading: "Councillor, City - Wards 1, 5", wards: [ 1, 5 ], candidates: [
        candidate(name: "Singh, Navjit", campaign_phone: "905.555.0111")
      ]),
      office(code: "cr15", heading: "Councillor, Regional - Wards 1, 5", wards: [ 1, 5 ], candidates: [
        candidate(name: "Toor, Gurpreet")
      ]),
      office(code: "pdsb15", heading: "Trustee, Peel District School Board - Wards 1, 5", wards: [ 1, 5 ], candidates: [
        candidate(name: "Brown, Kathy")
      ]),
      office(code: "monavenir", heading: "Trustee, Conseil scolaire catholique MonAvenir", wards: (1..10).to_a)
    ])

    counts = @raw_ingestion.brampton_candidates_loader.load(json_content: payload)

    assert_equal "complete", @raw_ingestion.reload.status
    assert_equal({ races: 5, candidates: 4, withdrawn: 0, skipped_offices: 0 }, counts)

    mayor = @election.races.find_by!(office_type: "mayor")
    assert mayor.at_large_district_type?
    assert_nil mayor.district_number
    assert_nil mayor.district_name
    avi = mayor.candidates.sole
    assert_equal "Dhaliwal", avi.last_name
    assert_equal "Avi", avi.first_name
    assert_equal "active", avi.status
    assert_equal Date.new(2026, 5, 4), avi.nomination_date
    assert_equal "416.882.1200", avi.phone
    assert_equal "http://www.avidhaliwal.com", avi.website
    assert_equal 2, avi.social_links.size
    assert avi.last_seen_at.present?

    # City and regional councillors share a district, so office_body keeps
    # their races apart under the same district_number.
    city = @election.races.find_by!(office_type: "councillor", office_body: "Brampton City Council")
    regional = @election.races.find_by!(office_type: "councillor", office_body: "Region of Peel Council")
    assert_equal 1, city.district_number
    assert_equal 1, regional.district_number
    assert_equal "Wards 1, 5", city.district_name
    assert city.ward_district_type?
    assert_equal [ 1, 5 ], city.metadata["ward_numbers"]
    assert_equal "cc15", city.metadata["office_code"]
    assert_equal "905.555.0111", city.candidates.sole.phone

    pdsb = @election.races.find_by!(office_body: "Peel District School Board")
    assert pdsb.school_board_ward_district_type?
    assert_equal 1, pdsb.district_number

    monavenir = @election.races.find_by!(office_body: "Conseil scolaire catholique MonAvenir")
    assert monavenir.at_large_district_type?
    assert_nil monavenir.district_number

    # The page lists every ward for an at-large race; recording that would make
    # ward_numbers mean two different things, so it stays unset.
    assert_nil mayor.metadata["ward_numbers"]
    assert_nil monavenir.metadata["ward_numbers"]
  end

  test "reruns update in place without duplicating races or candidates" do
    first = body(offices: [ office(code: "mayor", heading: "Mayor", wards: [ 1 ], candidates: [
      candidate(name: "Bhatt, Jagruti")
    ]) ])
    @raw_ingestion.brampton_candidates_loader.load(json_content: first)

    updated = body(offices: [ office(code: "mayor", heading: "Mayor", wards: [ 1 ], candidates: [
      candidate(name: "Bhatt, Jagruti", email: "connect@jagrutibhatt.ca")
    ]) ])
    counts = @raw_ingestion.brampton_candidates_loader.load(json_content: updated)

    assert_equal({ races: 0, candidates: 0, withdrawn: 0, skipped_offices: 0 }, counts)
    race = @election.races.find_by!(office_type: "mayor")
    assert_equal 1, race.candidates.count
    assert_equal "connect@jagrutibhatt.ca", race.candidates.sole.email
  end

  test "marks candidates flagged on the page as withdrawn" do
    payload = body(offices: [
      office(code: "cc34", heading: "Councillor, City - Wards 3, 4", wards: [ 3, 4 ], candidates: [
        candidate(name: "Campbell, Chris", withdrawn: true, date: "05012026", date_text: "5/1/2026")
      ])
    ])

    counts = @raw_ingestion.brampton_candidates_loader.load(json_content: payload)

    assert_equal 1, counts[:withdrawn]
    race = @election.races.find_by!(office_type: "councillor", district_number: 3)
    assert_equal "Wards 3, 4", race.district_name
    chris = race.candidates.sole
    assert_equal "withdrawn", chris.status
    assert_equal Date.new(2026, 5, 1), chris.nomination_date
  end

  test "a candidate who withdraws after a prior run flips to withdrawn" do
    active = body(offices: [ office(code: "cc34", heading: "Councillor, City - Wards 3, 4", wards: [ 3, 4 ],
      candidates: [ candidate(name: "Campbell, Chris") ]) ])
    @raw_ingestion.brampton_candidates_loader.load(json_content: active)

    gone = body(offices: [ office(code: "cc34", heading: "Councillor, City - Wards 3, 4", wards: [ 3, 4 ],
      candidates: [ candidate(name: "Campbell, Chris", withdrawn: true) ]) ])
    @raw_ingestion.brampton_candidates_loader.load(json_content: gone)

    race = @election.races.find_by!(office_type: "councillor", district_number: 3)
    assert_equal "withdrawn", race.candidates.sole.status
  end

  test "falls back to the visible filing date when the packed date is unusable" do
    payload = body(offices: [ office(code: "mayor", heading: "Mayor", wards: [ 1 ], candidates: [
      candidate(name: "Patel, Tirth", date: "not-a-date", date_text: "6/26/2026")
    ]) ])

    @raw_ingestion.brampton_candidates_loader.load(json_content: payload)

    assert_equal Date.new(2026, 6, 26), @election.races.sole.candidates.sole.nomination_date
  end

  test "single-name candidates keep the whole name" do
    payload = body(offices: [ office(code: "mayor", heading: "Mayor", wards: [ 1 ], candidates: [
      candidate(name: "Gursimranjit Singh")
    ]) ])

    @raw_ingestion.brampton_candidates_loader.load(json_content: payload)

    candidate = @election.races.sole.candidates.sole
    assert_equal "Gursimranjit Singh", candidate.full_name
    assert_equal "Gursimranjit Singh", candidate.last_name
    assert_nil candidate.first_name
    assert_equal "Gursimranjit Singh", candidate.display_name
  end

  test "skips offices with unrecognized codes without failing the load" do
    payload = body(offices: [
      office(code: "somethingnew", heading: "Trustee, Some New Board", wards: [ 1 ], candidates: [
        candidate(name: "Mystery, Person")
      ]),
      office(code: "mayor", heading: "Mayor", wards: (1..10).to_a, candidates: [ candidate(name: "Bhatt, Jagruti") ])
    ])

    counts = @raw_ingestion.brampton_candidates_loader.load(json_content: payload)

    assert_equal 1, counts[:skipped_offices]
    assert_equal 1, counts[:candidates]
    assert_equal "complete", @raw_ingestion.reload.status
    assert_equal 1, @election.races.count
  end

  test "fails the ingestion when the election is not seeded" do
    assert_raises(ActiveRecord::RecordNotFound) do
      @raw_ingestion.brampton_candidates_loader.load(json_content: body(year: "2030"))
    end

    assert_equal "failed", @raw_ingestion.reload.status
    assert @raw_ingestion.error_message.present?
  end

  test "fails the ingestion and re-raises on malformed payloads" do
    assert_raises(JSON::ParserError) do
      @raw_ingestion.brampton_candidates_loader.load(json_content: "not json")
    end

    assert_equal "failed", @raw_ingestion.reload.status
  end
end
