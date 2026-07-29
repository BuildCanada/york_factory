require "test_helper"

class Warehouse::RawIngestion::HamiltonCandidatesLoaderTest < ActiveSupport::TestCase
  setup do
    suffix = SecureRandom.hex(4)

    hamilton = Warehouse::Jurisdiction.find_or_create_by!(slug: "hamilton") do |j|
      j.name = "City of Hamilton"
      j.code = "HAM-ON"
      j.level = "municipal"
      j.fiscal_year_start_month = 1
      j.default_currency = "CAD"
    end
    @election = Warehouse::Election.find_or_create_by!(slug: "hamilton-2026") do |e|
      e.jurisdiction = hamilton
      e.name = "Hamilton 2026 General Municipal Election"
      e.kind = "municipal"
      e.election_date = Date.new(2026, 10, 26)
      e.nomination_close_date = Date.new(2026, 8, 21)
    end

    source = Warehouse::Source.create!(
      name: "election_hamilton_test_#{suffix}_2026",
      url: "https://www.hamilton.ca/city-council/municipal-election/candidates-third-party-advertisers/candidates",
      format: "hamilton_candidates_html"
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

  def office(section:, label: nil, candidates: [])
    { "section" => section, "label" => label, "candidates" => candidates }
  end

  def candidate(name:, phone: nil, email: nil)
    { "name" => name, "phone" => phone, "email" => email }
  end

  test "creates races and candidates for mayor, wards, and trustee districts" do
    payload = body(offices: [
      office(section: "mayor", candidates: [ candidate(name: "Cooper, Rob", phone: "289-768-2964") ]),
      office(section: "councillor", label: "Ward 1", candidates: [ candidate(name: "Wilson, Maureen") ]),
      office(section: "trustee", label: "Wards 5 & 10 - English Public", candidates: [ candidate(name: "Floyd, Seth") ]),
      office(section: "trustee", label: "Wards 1, 2 & 15 - English Separate", candidates: [ candidate(name: "Agro, Pat") ]),
      office(section: "trustee", label: "Conseil Scolaire Viamonde", candidates: [ candidate(name: "Roy, Marie") ])
    ])

    counts = @raw_ingestion.hamilton_candidates_loader.load(json_content: payload)

    assert_equal "complete", @raw_ingestion.reload.status
    assert_equal({ races: 5, candidates: 5, skipped_offices: 0 }, counts)

    mayor = @election.races.find_by!(office_type: "mayor")
    assert mayor.at_large_district_type?
    assert_nil mayor.district_number
    assert_nil mayor.district_name
    rob = mayor.candidates.sole
    assert_equal "Cooper", rob.last_name
    assert_equal "Rob", rob.first_name
    assert_equal "active", rob.status
    assert_equal "289-768-2964", rob.phone
    assert_nil rob.nomination_date
    assert rob.last_seen_at.present?

    ward1 = @election.races.find_by!(office_type: "councillor", district_number: 1)
    assert ward1.ward_district_type?
    assert_equal "Ward 1", ward1.district_name
    assert_equal [ 1 ], ward1.metadata["ward_numbers"]
    assert_nil ward1.office_body

    # Board shorthand on the page is expanded to the official board name.
    public_board = @election.races.find_by!(office_body: "Hamilton-Wentworth District School Board")
    assert public_board.school_board_ward_district_type?
    assert_equal 5, public_board.district_number
    assert_equal "Wards 5, 10", public_board.district_name
    assert_equal [ 5, 10 ], public_board.metadata["ward_numbers"]

    separate = @election.races.find_by!(office_body: "Hamilton-Wentworth Catholic District School Board")
    assert_equal 1, separate.district_number
    assert_equal "Wards 1, 2, 15", separate.district_name

    # The French-language boards elect one trustee city-wide.
    viamonde = @election.races.find_by!(office_body: "Conseil scolaire Viamonde")
    assert viamonde.at_large_district_type?
    assert_nil viamonde.district_number

    # At-large races cover the whole city, so they carry no ward list.
    assert_nil mayor.metadata["ward_numbers"]
    assert_nil viamonde.metadata["ward_numbers"]
  end

  test "the page's board-name typo still maps to the official name" do
    payload = body(offices: [
      office(section: "trustee", label: "Conseil Scolair Catholique MonAvenir",
        candidates: [ candidate(name: "Dupont, Jean") ])
    ])

    @raw_ingestion.hamilton_candidates_loader.load(json_content: payload)

    assert_equal "Conseil scolaire catholique MonAvenir", @election.races.sole.office_body
  end

  test "a councillor ward and a trustee district sharing a number stay separate races" do
    payload = body(offices: [
      office(section: "councillor", label: "Ward 5", candidates: [ candidate(name: "Beattie, Matt") ]),
      office(section: "trustee", label: "Ward 5 - English Separate", candidates: [ candidate(name: "Bishop, Mark") ])
    ])

    counts = @raw_ingestion.hamilton_candidates_loader.load(json_content: payload)

    assert_equal 2, counts[:races]
    assert_equal 2, @election.races.where(district_number: 5).count
  end

  test "a district with no candidates still creates the race" do
    payload = body(offices: [ office(section: "trustee", label: "Ward 1 - English Public") ])

    counts = @raw_ingestion.hamilton_candidates_loader.load(json_content: payload)

    assert_equal({ races: 1, candidates: 0, skipped_offices: 0 }, counts)
    assert_equal 0, @election.races.sole.candidates.count
  end

  test "reruns update in place without duplicating races or candidates" do
    first = body(offices: [ office(section: "councillor", label: "Ward 2",
      candidates: [ candidate(name: "Kroetsch, Cameron") ]) ])
    @raw_ingestion.hamilton_candidates_loader.load(json_content: first)

    updated = body(offices: [ office(section: "councillor", label: "Ward 2",
      candidates: [ candidate(name: "Kroetsch, Cameron", phone: "905-555-0100") ]) ])
    counts = @raw_ingestion.hamilton_candidates_loader.load(json_content: updated)

    assert_equal({ races: 0, candidates: 0, skipped_offices: 0 }, counts)
    race = @election.races.sole
    assert_equal 1, race.candidates.count
    assert_equal "905-555-0100", race.candidates.sole.phone
  end

  test "single-name candidates keep the whole name" do
    payload = body(offices: [ office(section: "mayor", candidates: [ candidate(name: "Cherry") ]) ])

    @raw_ingestion.hamilton_candidates_loader.load(json_content: payload)

    candidate = @election.races.sole.candidates.sole
    assert_equal "Cherry", candidate.full_name
    assert_equal "Cherry", candidate.last_name
    assert_nil candidate.first_name
  end

  test "skips an unrecognized school board without failing the load" do
    payload = body(offices: [
      office(section: "trustee", label: "Ward 3 - Some New Board", candidates: [ candidate(name: "Mystery, Person") ]),
      office(section: "mayor", candidates: [ candidate(name: "Cooper, Rob") ])
    ])

    counts = @raw_ingestion.hamilton_candidates_loader.load(json_content: payload)

    assert_equal 1, counts[:skipped_offices]
    assert_equal 1, counts[:candidates]
    assert_equal 1, @election.races.count
    assert_equal "complete", @raw_ingestion.reload.status
  end

  test "skips a councillor district with no ward number" do
    payload = body(offices: [
      office(section: "councillor", label: "At large?", candidates: [ candidate(name: "Mystery, Person") ])
    ])

    counts = @raw_ingestion.hamilton_candidates_loader.load(json_content: payload)

    assert_equal 1, counts[:skipped_offices]
    assert_equal 0, @election.races.count
  end

  test "fails the ingestion when the election is not seeded" do
    assert_raises(ActiveRecord::RecordNotFound) do
      @raw_ingestion.hamilton_candidates_loader.load(json_content: body(year: "2030"))
    end

    assert_equal "failed", @raw_ingestion.reload.status
    assert @raw_ingestion.error_message.present?
  end

  test "fails the ingestion and re-raises on malformed payloads" do
    assert_raises(JSON::ParserError) do
      @raw_ingestion.hamilton_candidates_loader.load(json_content: "not json")
    end

    assert_equal "failed", @raw_ingestion.reload.status
  end
end
