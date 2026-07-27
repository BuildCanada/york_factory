require "test_helper"

class Admin::ElectionRacesControllerTest < ActionDispatch::IntegrationTest
  setup do
    post user_session_path, params: { email: users(:admin).email, password: "password123" }

    jurisdiction = Warehouse::Jurisdiction.find_or_create_by!(slug: "ottawa") do |j|
      j.name = "City of Ottawa"
      j.code = "OTT-ON"
      j.level = "municipal"
      j.fiscal_year_start_month = 1
      j.default_currency = "CAD"
    end
    @election = Warehouse::Election.find_or_create_by!(slug: "ottawa-2026") do |e|
      e.jurisdiction = jurisdiction
      e.name = "Ottawa 2026 General Municipal Election"
      e.kind = "municipal"
      e.election_date = Date.new(2026, 10, 26)
    end
    @election.races.destroy_all
  end

  test "requires admin" do
    delete destroy_user_session_path
    get new_admin_election_race_path(@election)
    assert_redirected_to new_user_session_path
  end

  test "new and edit render" do
    get new_admin_election_race_path(@election)
    assert_response :success

    race = @election.races.create!(office_type: "mayor", district_type: "at_large")
    get edit_admin_election_race_path(@election, race)
    assert_response :success
  end

  test "creating a ward race records its ward numbers" do
    post admin_election_races_path(@election), params: {
      warehouse_election_race: {
        office_type: "councillor", district_type: "ward",
        district_number: "1", district_name: "Orléans East-Cumberland", office_body: ""
      },
      ward_numbers: "1"
    }

    assert_redirected_to admin_election_path(@election)
    race = @election.races.reload.sole
    assert_equal "councillor", race.office_type
    assert_equal 1, race.district_number
    assert_equal "Orléans East-Cumberland", race.district_name
    assert_equal [ 1 ], race.metadata["ward_numbers"]
    # Blank identity fields have to be NULL, not "".
    assert_nil race.office_body
  end

  test "creating an at-large race leaves the district and ward list unset" do
    post admin_election_races_path(@election), params: {
      warehouse_election_race: { office_type: "mayor", district_type: "at_large", district_number: "", district_name: "" },
      ward_numbers: ""
    }

    race = @election.races.reload.sole
    assert_nil race.district_number
    assert_nil race.district_name
    assert_nil race.metadata["ward_numbers"]
  end

  test "ward numbers accept any separator" do
    post admin_election_races_path(@election), params: {
      warehouse_election_race: { office_type: "trustee", district_type: "school_board_ward",
                                 district_number: "5", office_body: "Ottawa-Carleton District School Board" },
      ward_numbers: "10 & 5, 5"
    }

    assert_equal [ 5, 10 ], @election.races.reload.sole.metadata["ward_numbers"]
  end

  test "a duplicate race reports a validation error instead of a database exception" do
    @election.races.create!(office_type: "councillor", district_type: "ward", district_number: 1)

    post admin_election_races_path(@election), params: {
      warehouse_election_race: { office_type: "councillor", district_type: "ward", district_number: "1" },
      ward_numbers: "1"
    }

    assert_response :unprocessable_entity
    assert_select "div", text: /already has a race for this body and district/
    assert_equal 1, @election.races.reload.count
  end

  test "two bodies can share a district number" do
    post admin_election_races_path(@election), params: {
      warehouse_election_race: { office_type: "councillor", district_type: "ward", district_number: "1",
                                 office_body: "Ottawa City Council" }
    }
    post admin_election_races_path(@election), params: {
      warehouse_election_race: { office_type: "councillor", district_type: "ward", district_number: "1",
                                 office_body: "Some Regional Council" }
    }

    assert_equal 2, @election.races.reload.where(district_number: 1).count
  end

  test "updating a race keeps other metadata keys" do
    race = @election.races.create!(office_type: "councillor", district_type: "ward", district_number: 1,
      metadata: { "office_code" => "cc1", "ward_numbers" => [ 1 ] })

    patch admin_election_race_path(@election, race), params: {
      warehouse_election_race: { office_type: "councillor", district_type: "ward",
                                 district_number: "1", district_name: "Renamed Ward" },
      ward_numbers: "1, 2"
    }

    race.reload
    assert_equal "Renamed Ward", race.district_name
    assert_equal [ 1, 2 ], race.metadata["ward_numbers"]
    assert_equal "cc1", race.metadata["office_code"]
  end

  test "deleting a race deletes its candidates" do
    race = @election.races.create!(office_type: "mayor", district_type: "at_large")
    candidate = race.candidates.create!(full_name: "Leiper, Jeff")

    delete admin_election_race_path(@election, race)

    assert_redirected_to admin_election_path(@election)
    refute Warehouse::ElectionCandidate.exists?(candidate.id)
  end

  test "races of another election are out of reach" do
    other = Warehouse::Election.create!(slug: "elsewhere-2026", name: "Elsewhere 2026",
      kind: "municipal", election_date: Date.new(2026, 10, 26), jurisdiction: @election.jurisdiction)
    race = other.races.create!(office_type: "mayor", district_type: "at_large")

    get edit_admin_election_race_path(@election, race)

    assert_response :not_found
  end
end
