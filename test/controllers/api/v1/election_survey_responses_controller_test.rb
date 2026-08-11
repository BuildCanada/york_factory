require "test_helper"

class Api::V1::ElectionSurveyResponsesControllerTest < ActionDispatch::IntegrationTest
  SURVEY = "neighbourhood-priorities".freeze

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
    Warehouse::ElectionSurveyResponse.where(election: @election).delete_all

    @answers = {
      postal_code: "M5V 2T6", ward: "ward-10", tenure: "2to10",
      concern: "housing", housing_pace: "slow", fourplex: "yes"
    }
  end

  def submit(params)
    post api_v1_election_survey_responses_url("toronto-2026"), params: params
  end

  test "records a response and the subscriber behind it" do
    submit(email: "resident@example.com", name: "Rita Resident", survey_slug: SURVEY,
           survey_version: "1", region: "ward-10", postal_code: "M5V 2T6", answers: @answers)

    assert_response :created
    body = JSON.parse(response.body)
    assert_equal SURVEY, body["survey_slug"]
    assert_equal "ward-10", body["region"]

    assert_equal 1, @election.survey_responses.count
    record = @election.survey_responses.first
    assert_equal "housing", record.answers["concern"]
    assert_equal "1", record.survey_version
    assert_equal "M5V 2T6", record.postal_code

    subscriber = Subscriber.find_by(email: "resident@example.com")
    assert subscriber, "the survey should upsert a subscriber"
    assert_equal "survey", subscriber.source
    assert_equal "Rita", subscriber.first_name
    assert_equal "Resident", subscriber.last_name
  end

  test "the postal code is stored canonically whatever form it arrives in" do
    submit(email: "unspaced@example.com", name: "Una Unspaced", survey_slug: SURVEY,
           postal_code: "m5v2t6", answers: @answers)

    # warehouse.postal_codes keys on the spaced form, so a later ward backfill
    # from this column depends on it being canonical here.
    assert_equal "M5V 2T6", @election.survey_responses.first.postal_code
  end

  test "a junk postal code is dropped rather than costing us the answers" do
    submit(email: "junk@example.com", name: "Jo Junk", survey_slug: SURVEY,
           postal_code: "not a postcode", answers: @answers)

    assert_response :created
    assert_equal 1, @election.survey_responses.count
    assert_nil @election.survey_responses.first.postal_code
  end

  test "re-submitting updates the same row rather than adding one" do
    submit(email: "repeat@example.com", name: "Ray Repeat", survey_slug: SURVEY,
           region: "ward-10", answers: @answers)
    assert_response :created

    submit(email: "repeat@example.com", name: "Ray Repeat", survey_slug: SURVEY,
           region: "ward-11", answers: @answers.merge(concern: "transit"))

    assert_response :ok
    assert_equal 1, @election.survey_responses.count
    record = @election.survey_responses.first
    assert_equal "transit", record.answers["concern"]
    assert_equal "ward-11", record.region
  end

  test "two surveys in one election are kept apart" do
    submit(email: "two@example.com", name: "Tam Two", survey_slug: SURVEY, answers: @answers)
    submit(email: "two@example.com", name: "Tam Two", survey_slug: "budget-2027", answers: @answers)

    assert_response :created
    assert_equal 2, @election.survey_responses.count
  end

  test "an email is required" do
    assert_no_difference "Warehouse::ElectionSurveyResponse.count" do
      submit(name: "Anon", survey_slug: SURVEY, answers: @answers)
    end

    assert_response :unprocessable_entity
    assert_includes JSON.parse(response.body)["errors"], "Email is required"
  end

  test "answers are required" do
    assert_no_difference "Warehouse::ElectionSurveyResponse.count" do
      submit(email: "empty@example.com", name: "Emma Empty", survey_slug: SURVEY)
    end

    assert_response :unprocessable_entity
    assert_includes JSON.parse(response.body)["errors"], "Answers are required"
  end

  test "an over-long answer is rejected" do
    assert_no_difference "Warehouse::ElectionSurveyResponse.count" do
      submit(email: "spammy@example.com", name: "Sam Spam", survey_slug: SURVEY,
             answers: { other_issue: "x" * 3_000 })
    end

    assert_response :unprocessable_entity
  end

  test "a response on an unknown election is a 404" do
    post api_v1_election_survey_responses_url("nowhere-2026"),
      params: { email: "lost@example.com", survey_slug: SURVEY, answers: @answers }

    assert_response :not_found
  end

  test "a draft election takes no responses" do
    @election.update!(published_at: nil)

    assert_no_difference "Warehouse::ElectionSurveyResponse.count" do
      submit(email: "early@example.com", name: "Ellie Early", survey_slug: SURVEY, answers: @answers)
    end

    assert_response :not_found
  end

  test "the response never echoes back a name we already had on file" do
    submit(email: "known@example.com", name: "Nell Known", survey_slug: SURVEY, answers: @answers)
    assert_equal "Nell", Subscriber.find_by(email: "known@example.com").first_name

    # Someone who doesn't own the address submits it without a name. The reply
    # must not tell them whose address it is.
    submit(email: "known@example.com", survey_slug: SURVEY, answers: @answers)

    assert_response :ok
    assert_nil JSON.parse(response.body)["name"]
  end

  test "the tallied question list is capped" do
    submit(email: "capped@example.com", name: "Cap Ped", survey_slug: SURVEY, answers: @answers)

    over_cap = Array.new(Api::V1::ElectionSurveyResponsesController::MAX_TALLY_QUESTIONS + 20) { |i| "q#{i}" }
    get api_v1_election_survey_responses_url("toronto-2026"),
      params: { survey_slug: SURVEY, question_ids: over_cap.join(",") }

    assert_response :success
    tallies = JSON.parse(response.body)["data"]["tallies"]
    assert_equal Api::V1::ElectionSurveyResponsesController::MAX_TALLY_QUESTIONS, tallies.size
  end

  test "index tallies the requested questions and can narrow to a ward" do
    submit(email: "a@example.com", name: "A One", survey_slug: SURVEY,
           region: "ward-10", answers: @answers)
    submit(email: "b@example.com", name: "B Two", survey_slug: SURVEY,
           region: "ward-10", answers: @answers.merge(concern: "transit"))
    submit(email: "c@example.com", name: "C Three", survey_slug: SURVEY,
           region: "ward-11", answers: @answers)

    get api_v1_election_survey_responses_url("toronto-2026"),
      params: { survey_slug: SURVEY, question_ids: "concern" }

    assert_response :success
    data = JSON.parse(response.body)["data"]
    assert_equal 3, data["total"]
    assert_equal({ "housing" => 2, "transit" => 1 }, data["tallies"]["concern"])

    get api_v1_election_survey_responses_url("toronto-2026"),
      params: { survey_slug: SURVEY, question_ids: "concern", region: "ward-11" }

    data = JSON.parse(response.body)["data"]
    assert_equal 1, data["total"]
    assert_equal({ "housing" => 1 }, data["tallies"]["concern"])
  end
end
