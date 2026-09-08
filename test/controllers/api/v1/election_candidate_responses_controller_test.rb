require "test_helper"

class Api::V1::ElectionCandidateResponsesControllerTest < ActionDispatch::IntegrationTest
  setup do
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
    @election.update!(published_at: 1.day.ago)
    @election.surveys.destroy_all

    @survey = @election.surveys.create!(
      slug: "candidate-questionnaire", audience: "candidate", version: "1",
      meta: { "title" => "Toronto 2026 candidate questionnaire" },
      published_at: 1.day.ago
    )
    @survey.questions.create!(
      question_id: "housing_as_of_right", step_id: "housing", step_title: "Housing",
      step_position: 0, position: 0, question_type: "radio",
      label: "More housing as-of-right?",
      options: [ { "value" => "yes", "label" => "Yes" } ]
    )

    @ward_11 = @election.races.create!(
      office_type: "councillor", district_type: "ward", district_number: 11,
      district_name: "University-Rosedale"
    )
    @ward_14 = @election.races.create!(
      office_type: "councillor", district_type: "ward", district_number: 14,
      district_name: "Toronto-Danforth"
    )
  end

  def body
    JSON.parse(response.body)["data"]
  end

  def candidate(race:, full_name:, first_name: nil, last_name: nil, email: nil)
    Warehouse::ElectionCandidate.create!(
      race: race, full_name: full_name, first_name: first_name,
      last_name: last_name, email: email, status: "active"
    )
  end

  def response_for(candidate, status: "published", answers: { "housing_as_of_right" => "yes" })
    @survey.candidate_responses.create!(
      candidate: candidate, answers: answers, explanations: {},
      survey_version: "1", source: "form", status: status
    )
  end

  def admin_token
    admin = users(:admin)
    admin.update!(role: "admin") unless admin.admin?
    application = Doorkeeper::Application.create!(
      name: "preview-#{SecureRandom.hex(4)}", redirect_uri: "https://example.com/cb"
    )
    Doorkeeper::AccessToken.create!(application: application, resource_owner_id: admin.id)
  end

  test "index lists published responses with the candidate's ward" do
    response_for(candidate(race: @ward_14, full_name: "Ward, Nicki",
      first_name: "Nicki", last_name: "Ward"))

    get api_v1_election_candidate_responses_url("toronto-2026")

    assert_response :success
    assert_equal 1, body.size
    assert_equal "Nicki Ward", body.first["candidate_name"]
    assert_equal "Ward, Nicki", body.first["full_name"]
    assert_equal 14, body.first["ward"]
    assert_equal({ "housing_as_of_right" => "yes" }, body.first["answers"])
    assert_equal "candidate-questionnaire", body.first["survey_slug"]
  end

  # The importer lands every response as a draft on purpose: a candidate's
  # answers are attributed public statements, released after review. A draft
  # leaking here would publish a position nobody signed off on.
  test "index hides a response that has not been published" do
    response_for(candidate(race: @ward_14, full_name: "Ward, Nicki"), status: "draft")
    response_for(candidate(race: @ward_11, full_name: "Dean, Laura"), status: "submitted")

    get api_v1_election_candidate_responses_url("toronto-2026")

    assert_response :success
    assert_empty body
  end

  test "an admin token previews unpublished responses" do
    response_for(candidate(race: @ward_14, full_name: "Ward, Nicki"), status: "draft")

    get api_v1_election_candidate_responses_url("toronto-2026"),
      headers: { "Authorization" => "Bearer #{admin_token.token}" }

    assert_response :success
    assert_equal [ "Ward, Nicki" ], body.map { |r| r["full_name"] }
  end

  # The survey gate is separate from the response gate: a questionnaire still
  # being authored must not leak, even if a response on it were marked published.
  test "index serves nothing while the survey itself is unpublished" do
    @survey.update!(published_at: nil)
    response_for(candidate(race: @ward_14, full_name: "Ward, Nicki"))

    get api_v1_election_candidate_responses_url("toronto-2026")

    assert_response :success
    assert_empty body
  end

  test "index ignores resident surveys" do
    resident = @election.surveys.create!(
      slug: "city-priorities", audience: "resident", version: "2",
      published_at: 1.day.ago
    )
    assert resident.persisted?
    response_for(candidate(race: @ward_11, full_name: "Dean, Laura"))

    get api_v1_election_candidate_responses_url("toronto-2026")

    assert_equal [ "candidate-questionnaire" ], body.map { |r| r["survey_slug"] }
  end

  test "survey_slug narrows to one questionnaire" do
    other = @election.surveys.create!(
      slug: "mayoral-questionnaire", audience: "candidate", version: "1",
      published_at: 1.day.ago
    )
    other.candidate_responses.create!(
      candidate: candidate(race: @ward_11, full_name: "Dean, Laura"),
      answers: {}, explanations: {}, survey_version: "1", source: "form",
      status: "published"
    )
    response_for(candidate(race: @ward_14, full_name: "Ward, Nicki"))

    get api_v1_election_candidate_responses_url("toronto-2026"),
      params: { survey_slug: "candidate-questionnaire" }

    assert_equal [ "Ward, Nicki" ], body.map { |r| r["full_name"] }
  end

  test "ward narrows to one council district" do
    response_for(candidate(race: @ward_14, full_name: "Ward, Nicki"))
    response_for(candidate(race: @ward_11, full_name: "Dean, Laura"))

    get api_v1_election_candidate_responses_url("toronto-2026"), params: { ward: "11" }

    assert_equal [ "Dean, Laura" ], body.map { |r| r["full_name"] }
  end

  # The tracker keys wards as "04", so the filter has to read a padded number
  # rather than compare it as a string. "08" and "09" are the ones that bite:
  # Integer() treats a leading zero as octal, where 8 and 9 are not digits.
  test "ward accepts a zero-padded number" do
    %w[04 08 09].each_with_index do |padded, index|
      number = padded.to_i
      race = @election.races.create!(
        office_type: "councillor", district_type: "ward", district_number: number,
        district_name: "Ward #{number}"
      )
      response_for(candidate(race: race, full_name: "Padded#{index}, Test"))

      get api_v1_election_candidate_responses_url("toronto-2026"), params: { ward: padded }

      assert_response :success
      assert_equal [ number ], body.map { |r| r["ward"] },
        "ward=#{padded} should resolve to ward #{number}"
    end
  end

  test "a ward that is not a number matches nothing rather than everything" do
    response_for(candidate(race: @ward_14, full_name: "Ward, Nicki"))

    get api_v1_election_candidate_responses_url("toronto-2026"), params: { ward: "downtown" }

    assert_response :success
    assert_empty body
  end

  # entered_by names the staff member who transcribed a reply — internal
  # provenance, not part of the position being published.
  test "index never exposes who entered the response" do
    record = response_for(candidate(race: @ward_14, full_name: "Ward, Nicki"))
    record.update!(entered_by: "staff@buildcanada.com")

    get api_v1_election_candidate_responses_url("toronto-2026")

    refute body.first.key?("entered_by")
  end

  test "a candidate with no split name falls back to the roster spelling" do
    response_for(candidate(race: @ward_14, full_name: "Hoàng-Lefranc, Andi"))

    get api_v1_election_candidate_responses_url("toronto-2026")

    assert_equal "Andi Hoàng-Lefranc", body.first["candidate_name"]
  end

  test "an unpublished election serves no candidate responses" do
    @election.update!(published_at: nil)
    response_for(candidate(race: @ward_14, full_name: "Ward, Nicki"))

    get api_v1_election_candidate_responses_url("toronto-2026")

    assert_response :not_found
  end

  test "index 404s for an unknown election" do
    get api_v1_election_candidate_responses_url("no-such-election")

    assert_response :not_found
  end
end
