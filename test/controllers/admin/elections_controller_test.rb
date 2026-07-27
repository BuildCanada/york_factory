require "test_helper"

class Admin::ElectionsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    post user_session_path, params: { email: users(:admin).email, password: "password123" }

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
    race = @election.races.find_or_create_by!(office_type: "mayor", district_type: "at_large")
    @candidate = race.candidates.find_or_create_by!(full_name: "Chow, Olivia") do |c|
      c.first_name = "Olivia"
      c.last_name = "Chow"
      c.status = "active"
    end
  end

  test "requires admin" do
    delete destroy_user_session_path
    get admin_elections_path
    assert_redirected_to new_user_session_path
  end

  test "index and show render" do
    get admin_elections_path
    assert_response :success
    assert_select "a", text: @election.name

    get admin_election_path(@election)
    assert_response :success
    assert_select "tr#candidate-#{@candidate.id}"
  end

  test "uploading a photo attaches it and marks the source manual" do
    patch admin_election_candidate_path(@candidate), params: {
      warehouse_election_candidate: {
        photo: fixture_file_upload("test-image.jpg", "image/jpeg"),
        photo_attribution: "Campaign photo"
      }
    }

    assert_redirected_to admin_election_path(@election, anchor: "candidate-#{@candidate.id}")
    @candidate.reload
    assert @candidate.photo.attached?
    assert_equal "manual", @candidate.photo_source
    assert_equal "Campaign photo", @candidate.photo_attribution
  end

  test "purging removes the photo and provenance" do
    @candidate.photo.attach(io: StringIO.new("bytes"), filename: "x.jpg", content_type: "image/jpeg")
    @candidate.update!(photo_source: "manual", photo_attribution: "x")

    patch admin_election_candidate_path(@candidate), params: {
      warehouse_election_candidate: { purge_photo: "1", photo_attribution: "" }
    }

    @candidate.reload
    refute @candidate.photo.attached?
    assert_nil @candidate.photo_source
  end

  test "creating an election with an existing jurisdiction" do
    post admin_elections_path, params: {
      warehouse_election: {
        name: "Ottawa 2026 General Municipal Election", slug: "ottawa-2026", kind: "municipal",
        jurisdiction_id: @election.jurisdiction_id,
        election_date: "2026-10-26", nomination_close_date: "2026-08-21"
      }
    }

    election = Warehouse::Election.find_by!(slug: "ottawa-2026")
    assert_redirected_to admin_election_path(election)
    assert_equal Date.new(2026, 8, 21), election.nomination_close_date
  end

  test "creating an election also creates a new jurisdiction when one is named" do
    assert_difference -> { Warehouse::Jurisdiction.count }, 1 do
      post admin_elections_path, params: {
        warehouse_election: {
          name: "Ottawa 2026 General Municipal Election", slug: "ottawa-2026",
          kind: "municipal", election_date: "2026-10-26"
        },
        new_jurisdiction: { name: "City of Ottawa", slug: "ottawa", code: "OTT-ON", level: "municipal" }
      }
    end

    election = Warehouse::Election.find_by!(slug: "ottawa-2026")
    assert_equal "City of Ottawa", election.jurisdiction.name
    assert_equal "OTT-ON", election.jurisdiction.code
  end

  test "a new jurisdiction reuses an existing slug rather than duplicating it" do
    assert_no_difference -> { Warehouse::Jurisdiction.count } do
      post admin_elections_path, params: {
        warehouse_election: { name: "Toronto 2030", slug: "toronto-2030", kind: "municipal", election_date: "2030-10-28" },
        new_jurisdiction: { name: "City of Toronto", slug: "toronto" }
      }
    end

    assert_equal "toronto", Warehouse::Election.find_by!(slug: "toronto-2030").jurisdiction.slug
  end

  test "an invalid election re-renders the form" do
    post admin_elections_path, params: { warehouse_election: { name: "", slug: "", kind: "municipal" } }

    assert_response :unprocessable_entity
    assert_select "div", text: /can't be blank/
  end

  test "updating an election" do
    patch admin_election_path(@election), params: {
      warehouse_election: { name: "Toronto 2026 (revised)", slug: @election.slug,
                            kind: @election.kind, jurisdiction_id: @election.jurisdiction_id,
                            election_date: @election.election_date.to_s }
    }

    assert_redirected_to admin_election_path(@election)
    assert_equal "Toronto 2026 (revised)", @election.reload.name
  end

  test "deleting an election removes its races and candidates" do
    delete admin_election_path(@election)

    assert_redirected_to admin_elections_path
    refute Warehouse::Election.exists?(@election.id)
    refute Warehouse::ElectionCandidate.exists?(@candidate.id)
  end

  test "the show page offers the management actions" do
    get admin_election_path(@election)

    assert_response :success
    assert_select "a[href=?]", new_admin_election_race_path(@election)
    assert_select "a[href=?]", edit_admin_election_path(@election)
    assert_select "a[href=?]", edit_admin_election_candidate_path(@candidate)
    assert_select "a[href=?]", new_admin_election_race_candidate_path(@candidate.race)
  end

  test "fetch_photo_suggestions queues jobs only for active candidates without photos" do
    race = @candidate.race
    race.candidates.find_or_create_by!(full_name: "Gone, Person") do |c|
      c.status = "withdrawn"
    end
    with_photo = race.candidates.find_or_create_by!(full_name: "Has, Photo") { |c| c.status = "active" }
    with_photo.photo.attach(io: StringIO.new("bytes"), filename: "y.jpg", content_type: "image/jpeg")

    assert_enqueued_jobs 1, only: Warehouse::ElectionCandidate::PhotoSuggester::SuggestJob do
      post fetch_photo_suggestions_admin_election_path(@election)
    end
    assert_redirected_to admin_election_path(@election)
  end
end
