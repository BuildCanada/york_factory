require "test_helper"

class Warehouse::RawIngestion::TorontoCandidatesLoaderTest < ActiveSupport::TestCase
  setup do
    suffix = SecureRandom.hex(4)

    toronto = Warehouse::Jurisdiction.find_or_create_by!(slug: "toronto") do |j|
      j.name = "City of Toronto"
      j.code = "TOR-ON"
      j.level = "municipal"
      j.fiscal_year_start_month = 1
      j.default_currency = "CAD"
    end
    @election = Warehouse::Election.find_or_create_by!(slug: "toronto-2026") do |e|
      e.jurisdiction = toronto
      e.name = "Toronto 2026 General Municipal Election"
      e.kind = "municipal"
      e.election_date = Date.new(2026, 10, 26)
    end

    source = Warehouse::Source.create!(
      name: "election_toronto_test_#{suffix}_2026",
      url: "https://www.toronto.ca/data/elections/candidate_list",
      format: "toronto_candidates_json"
    )
    @raw_ingestion = source.raw_ingestions.create!(
      fetched_at: Time.current,
      raw_file_path: "raw/test/#{suffix}.json",
      checksum: SecureRandom.hex(32),
      status: :pending
    )
  end

  def body(year: "2026", mayor: [], councillor: [], trustee: [], withdrawn: [])
    JSON.generate(
      "year" => year, "mayor" => mayor, "councillor" => councillor,
      "trustee" => trustee, "withdrawn" => withdrawn
    )
  end

  def candidate(name:, first:, last:, office:, status: "Active", nomination: "14-May-2026",
                email: "", phone: nil, socials: [], date_withdrawn: nil, ward: nil)
    entry = {
      "name" => name, "dateNomination" => nomination, "office" => office, "status" => status,
      "email" => email, "phone" => phone, "socialMedias" => socials,
      "firstName" => first, "lastName" => last
    }
    entry["dateWithdrawn"] = date_withdrawn if date_withdrawn
    entry["ward"] = ward if ward
    entry
  end

  test "creates races and candidates for mayor, councillor wards, and trustee boards" do
    payload = body(
      mayor: [ candidate(name: "Chow, Olivia", first: "Olivia", last: "Chow", office: 1,
                         socials: [ { "name" => "web", "url" => "https://oliviachow.ca" },
                                    { "name" => "twitter", "url" => "https://x.com/oliviachow" } ]) ],
      councillor: [ { "name" => "Name:5", "num" => "5", "n" => 5,
                      "candidate" => [ candidate(name: "Adib, Alaa", first: "Ala'a", last: "Adib", office: 2,
                                                 email: "alaa@alaaadib.ca", nomination: "01-May-2026") ] } ],
      trustee: [ { "id" => 3, "ward" => [ { "name" => "1", "num" => "1",
                   "candidate" => [ candidate(name: "de Dovitiis, Matias", first: "Matias", last: "de Dovitiis", office: 3) ] } ] } ]
    )

    counts = @raw_ingestion.toronto_candidates_loader.load(json_content: payload)

    assert_equal "complete", @raw_ingestion.reload.status
    assert_equal({ races: 3, candidates: 3, withdrawn: 0 }, counts)

    mayor_race = @election.races.find_by!(office_type: "mayor")
    assert mayor_race.at_large_district_type?
    chow = mayor_race.candidates.find_by!(full_name: "Chow, Olivia")
    assert_equal "Olivia", chow.first_name
    assert_equal "active", chow.status
    assert_equal Date.new(2026, 5, 14), chow.nomination_date
    assert_equal "https://oliviachow.ca", chow.website
    assert_equal 2, chow.social_links.size
    assert chow.last_seen_at.present?

    ward5 = @election.races.find_by!(office_type: "councillor", district_number: 5)
    assert_equal "York South-Weston", ward5.district_name
    adib = ward5.candidates.find_by!(full_name: "Adib, Alaa")
    assert_equal "alaa@alaaadib.ca", adib.email
    assert_nil adib.website

    tdsb = @election.races.find_by!(office_type: "trustee", district_number: 1)
    assert_equal "Toronto District School Board", tdsb.office_body
    assert tdsb.school_board_ward_district_type?
  end

  test "reruns update in place without duplicating races or candidates" do
    first = body(mayor: [ candidate(name: "Chow, Olivia", first: "Olivia", last: "Chow", office: 1) ])
    @raw_ingestion.toronto_candidates_loader.load(json_content: first)

    updated = body(mayor: [ candidate(name: "Chow, Olivia", first: "Olivia", last: "Chow", office: 1,
                                      email: "hello@oliviachow.ca") ])
    counts = @raw_ingestion.toronto_candidates_loader.load(json_content: updated)

    assert_equal({ races: 0, candidates: 0, withdrawn: 0 }, counts)
    race = @election.races.find_by!(office_type: "mayor")
    assert_equal 1, race.candidates.count
    assert_equal "hello@oliviachow.ca", race.candidates.sole.email
  end

  test "marks withdrawn candidates withdrawn even after they leave the active lists" do
    payload = body(
      withdrawn: [ candidate(name: "Nikolaou, Jonathan", first: "Jonathan", last: "Nikolaou",
                             office: 2, status: "Withdrawn", nomination: "19-May-2026",
                             date_withdrawn: "03-Jun-2026", ward: 4) ]
    )

    counts = @raw_ingestion.toronto_candidates_loader.load(json_content: payload)

    assert_equal 1, counts[:withdrawn]
    race = @election.races.find_by!(office_type: "councillor", district_number: 4)
    assert_equal "Parkdale-High Park", race.district_name
    withdrawn = race.candidates.find_by!(full_name: "Nikolaou, Jonathan")
    assert_equal "withdrawn", withdrawn.status
    assert_equal Date.new(2026, 6, 3), withdrawn.withdrawn_date
  end

  test "withdrawn entry wins over the active feeds within one run" do
    active = candidate(name: "Chow, Olivia", first: "Olivia", last: "Chow", office: 1)
    gone = candidate(name: "Chow, Olivia", first: "Olivia", last: "Chow", office: 1,
                     status: "Withdrawn", date_withdrawn: "03-Jun-2026")

    @raw_ingestion.toronto_candidates_loader.load(json_content: body(mayor: [ active ], withdrawn: [ gone ]))

    chow = @election.races.find_by!(office_type: "mayor").candidates.sole
    assert_equal "withdrawn", chow.status
  end

  test "skips withdrawn entries with unknown office codes" do
    payload = body(
      withdrawn: [ candidate(name: "Mystery, Person", first: "Person", last: "Mystery",
                             office: 42, status: "Withdrawn", ward: 1) ]
    )

    counts = @raw_ingestion.toronto_candidates_loader.load(json_content: payload)

    assert_equal 0, counts[:withdrawn]
    assert_equal "complete", @raw_ingestion.reload.status
  end

  test "fails the ingestion when the election is not seeded" do
    assert_raises(ActiveRecord::RecordNotFound) do
      @raw_ingestion.toronto_candidates_loader.load(json_content: body(year: "2030"))
    end

    assert_equal "failed", @raw_ingestion.reload.status
    assert @raw_ingestion.error_message.present?
  end

  test "fails the ingestion and re-raises on malformed payloads" do
    assert_raises(JSON::ParserError) do
      @raw_ingestion.toronto_candidates_loader.load(json_content: "not json")
    end

    assert_equal "failed", @raw_ingestion.reload.status
  end
end
