require "test_helper"

class Api::V1::ElectionSurveysControllerTest < ActionDispatch::IntegrationTest
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
      slug: "city-priorities", audience: "resident", version: "2",
      meta: { "title" => "Toronto priorities survey" }, published_at: 1.day.ago
    )
    @survey.questions.create!(
      question_id: "ward", step_id: "about-you", step_title: "About you",
      step_position: 0, position: 0, question_type: "select",
      label: "Which ward do you live in?", required: true, options_source: "wards"
    )
    @survey.questions.create!(
      question_id: "housing_pace", step_id: "housing", step_title: "Housing",
      step_position: 1, position: 0, question_type: "radio", label: "Pace?",
      options: [ { "value" => "slow", "label" => "Too slow" } ]
    )
  end

  def body
    JSON.parse(response.body)["data"]
  end

  test "index lists published surveys without their questions" do
    get api_v1_election_surveys_url("toronto-2026")
    assert_response :success

    assert_equal [ "city-priorities" ], body.map { |s| s["slug"] }
    assert_equal 2, body.first["question_count"]
    assert_not body.first.key?("steps")
  end

  test "index hides an unpublished survey" do
    @election.surveys.create!(
      slug: "candidate-questionnaire", audience: "candidate", version: "1"
    )

    get api_v1_election_surveys_url("toronto-2026")
    assert_equal [ "city-priorities" ], body.map { |s| s["slug"] }
  end

  test "index can be filtered by audience" do
    @election.surveys.create!(
      slug: "candidate-questionnaire", audience: "candidate", version: "1",
      published_at: 1.day.ago
    )

    get api_v1_election_surveys_url("toronto-2026"), params: { audience: "candidate" }
    assert_equal [ "candidate-questionnaire" ], body.map { |s| s["slug"] }
  end

  test "show returns the question set grouped into ordered steps" do
    get api_v1_election_survey_url("toronto-2026", "city-priorities")
    assert_response :success

    assert_equal "2", body["version"]
    assert_equal %w[about-you housing], body["steps"].map { |s| s["id"] }
    assert_equal "Which ward do you live in?", body["steps"].first["questions"].first["label"]
  end

  test "show resolves ward options from the election's councillor races" do
    race = @election.races.find_or_create_by!(
      office_type: "councillor", district_type: "ward", district_number: 7
    ) { |r| r.district_name = "Humber River-Black Creek" }
    assert race.persisted?

    get api_v1_election_survey_url("toronto-2026", "city-priorities")

    ward = body["steps"].first["questions"].first
    assert_includes ward["options"], { "value" => "ward-7", "label" => "7 — Humber River-Black Creek" }
    # "I'm not sure" is always offered last, since the question is required.
    assert_equal "unsure", ward["options"].last["value"]
  end

  test "show 404s for an unpublished survey" do
    @election.surveys.create!(
      slug: "candidate-questionnaire", audience: "candidate", version: "1"
    )

    get api_v1_election_survey_url("toronto-2026", "candidate-questionnaire")
    assert_response :not_found
  end

  test "show 404s for an unknown survey slug" do
    get api_v1_election_survey_url("toronto-2026", "no-such-survey")
    assert_response :not_found
  end

  test "an unpublished election serves no surveys" do
    @election.update!(published_at: nil)

    get api_v1_election_surveys_url("toronto-2026")
    assert_response :not_found
  end
end
