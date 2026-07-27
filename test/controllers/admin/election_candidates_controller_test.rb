require "test_helper"

class Admin::ElectionCandidatesControllerTest < ActionDispatch::IntegrationTest
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
    @race = @election.races.create!(office_type: "mayor", district_type: "at_large")
  end

  test "requires admin" do
    delete destroy_user_session_path
    get new_admin_election_race_candidate_path(@race)
    assert_redirected_to new_user_session_path
  end

  test "new and edit render" do
    get new_admin_election_race_candidate_path(@race)
    assert_response :success

    candidate = @race.candidates.create!(full_name: "Leiper, Jeff")
    get edit_admin_election_candidate_path(candidate)
    assert_response :success
  end

  test "creating a candidate with contact details and social links" do
    post admin_election_race_candidates_path(@race), params: {
      warehouse_election_candidate: {
        full_name: "Leiper, Jeff", first_name: "Jeff", last_name: "Leiper", status: "active",
        nomination_date: "2026-05-01", email: "info@leiper2026.ca", phone: "613-416-7437",
        website: "https://www.leiper2026.ca"
      },
      social_links: "Facebook|https://facebook.com/jeffleiperottawa\nX|https://x.com/LeiperOttawa\n"
    }

    candidate = @race.candidates.reload.sole
    assert_redirected_to admin_election_path(@election, anchor: "candidate-#{candidate.id}")
    assert_equal "Jeff Leiper", candidate.display_name
    assert_equal "active", candidate.status
    assert_equal Date.new(2026, 5, 1), candidate.nomination_date
    assert_equal "info@leiper2026.ca", candidate.email
    assert_equal "https://www.leiper2026.ca", candidate.website
    # Stored the way the city feeds publish them, with names downcased.
    assert_equal [ { "name" => "facebook", "url" => "https://facebook.com/jeffleiperottawa" },
                   { "name" => "x", "url" => "https://x.com/LeiperOttawa" } ], candidate.social_links
  end

  test "a social-links line with no label is treated as a website" do
    post admin_election_race_candidates_path(@race), params: {
      warehouse_election_candidate: { full_name: "Lawson, Alex", status: "active" },
      social_links: "https://votealex.ca\n\n"
    }

    assert_equal [ { "name" => "web", "url" => "https://votealex.ca" } ],
      @race.candidates.reload.sole.social_links
  end

  test "a duplicate name in the same race reports a validation error" do
    @race.candidates.create!(full_name: "Leiper, Jeff")

    post admin_election_race_candidates_path(@race), params: {
      warehouse_election_candidate: { full_name: "Leiper, Jeff", status: "active" }
    }

    assert_response :unprocessable_entity
    assert_select "div", text: /has already been taken/
    assert_equal 1, @race.candidates.reload.count
  end

  test "a candidate with no name re-renders the form" do
    post admin_election_race_candidates_path(@race), params: {
      warehouse_election_candidate: { full_name: "", status: "active" }
    }

    assert_response :unprocessable_entity
    assert_equal 0, @race.candidates.reload.count
  end

  test "the same name may appear in two different races" do
    other = @election.races.create!(office_type: "councillor", district_type: "ward", district_number: 1)
    @race.candidates.create!(full_name: "Leiper, Jeff")

    post admin_election_race_candidates_path(other), params: {
      warehouse_election_candidate: { full_name: "Leiper, Jeff", status: "active" }
    }

    assert_equal 1, other.candidates.reload.count
  end

  test "editing a candidate updates the fields and clears social links when emptied" do
    candidate = @race.candidates.create!(full_name: "Chebib, Zed", status: "active",
      social_links: [ { "name" => "facebook", "url" => "https://facebook.com/zed" } ])

    patch admin_election_candidate_path(candidate), params: {
      warehouse_election_candidate: { full_name: "Chebib, Zed", first_name: "Zed", last_name: "Chebib",
                                      status: "withdrawn", withdrawn_date: "2026-07-20" },
      social_links: ""
    }

    assert_redirected_to admin_election_path(@election, anchor: "candidate-#{candidate.id}")
    candidate.reload
    assert_equal "withdrawn", candidate.status
    assert_equal Date.new(2026, 7, 20), candidate.withdrawn_date
    assert_equal [], candidate.social_links
  end

  test "the photo-only form on the election page leaves other fields alone" do
    candidate = @race.candidates.create!(full_name: "Sutcliffe, Mark", status: "active",
      website: "https://marksutcliffe2026.ca",
      social_links: [ { "name" => "web", "url" => "https://marksutcliffe2026.ca" } ])

    patch admin_election_candidate_path(candidate), params: {
      warehouse_election_candidate: {
        photo: fixture_file_upload("test-image.jpg", "image/jpeg"), photo_attribution: "Campaign photo"
      }
    }

    candidate.reload
    assert candidate.photo.attached?
    assert_equal "manual", candidate.photo_source
    assert_equal "https://marksutcliffe2026.ca", candidate.website
    assert_equal 1, candidate.social_links.size
  end

  test "deleting a candidate" do
    candidate = @race.candidates.create!(full_name: "Westaway, Peter")

    delete admin_election_candidate_path(candidate)

    assert_redirected_to admin_election_path(@election)
    refute Warehouse::ElectionCandidate.exists?(candidate.id)
  end
end
