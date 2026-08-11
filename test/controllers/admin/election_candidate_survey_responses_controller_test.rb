require "test_helper"

class Admin::ElectionCandidateSurveyResponsesControllerTest < ActionDispatch::IntegrationTest
  setup do
    post user_session_path, params: { email: users(:admin).email, password: "password123" }

    jurisdiction = Warehouse::Jurisdiction.find_or_create_by!(slug: "admin-q-city") do |j|
      j.name = "Admin Q City"
      j.code = "AQC-ON"
      j.level = "municipal"
      j.fiscal_year_start_month = 1
      j.default_currency = "CAD"
    end
    @election = Warehouse::Election.create!(
      jurisdiction: jurisdiction, slug: "admin-q-2026", name: "Admin Q 2026",
      kind: "municipal", election_date: Date.new(2026, 10, 26)
    )
    race = @election.races.create!(
      office_type: "councillor", district_type: "ward",
      district_number: 3, district_name: "Riverside"
    )
    @candidate = race.candidates.create!(full_name: "Quinn, Alex", status: "active")

    @survey = @election.surveys.create!(
      slug: "candidate-questionnaire", audience: "candidate", version: "1"
    )
    @survey.questions.create!(
      question_id: "housing", step_id: "policy", step_title: "Policy",
      question_type: "radio", label: "Housing?",
      options: [ { "value" => "build", "label" => "Build more" } ]
    )
    @survey.questions.create!(
      question_id: "transit", step_id: "policy", step_title: "Policy", position: 1,
      question_type: "textarea", label: "Transit plans?"
    )
  end

  def response_record
    @survey.candidate_responses.find_by(candidate: @candidate)
  end

  test "the entry form renders the questionnaire's questions" do
    get edit_admin_election_candidate_survey_response_path(@candidate)
    assert_response :success
    assert_select "select[name='answers[housing]']"
    assert_select "textarea[name='answers[transit]']"
    assert_select "textarea[name='explanations[housing]']"
  end

  test "saving records the answers, who entered them and how they arrived" do
    patch admin_election_candidate_survey_response_path(@candidate), params: {
      warehouse_election_candidate_survey_response: {
        status: "submitted", source: "email", notes: "Replied by email."
      },
      answers: { housing: "build", transit: "More buses." },
      explanations: { housing: "Supports as-of-right fourplexes." }
    }
    assert_redirected_to admin_election_path(@election, anchor: "candidate-#{@candidate.id}")

    saved = response_record
    assert_equal({ "housing" => "build", "transit" => "More buses." }, saved.answers)
    assert_equal "Supports as-of-right fourplexes.", saved.explanations["housing"]
    assert saved.submitted?
    assert saved.via_email?
    assert_equal "1", saved.survey_version
    assert saved.entered_by.present?
    assert saved.submitted_at.present?
  end

  test "blank answers are dropped rather than stored as empty strings" do
    patch admin_election_candidate_survey_response_path(@candidate), params: {
      warehouse_election_candidate_survey_response: { status: "draft", source: "phone" },
      answers: { housing: "build", transit: "   " }
    }

    saved = response_record
    assert_equal [ "housing" ], saved.answers.keys
    assert_equal [ "transit" ], saved.unanswered_question_ids
  end

  test "an answer to a question not in this survey is ignored, not an error" do
    patch admin_election_candidate_survey_response_path(@candidate), params: {
      warehouse_election_candidate_survey_response: { status: "draft", source: "admin" },
      answers: { housing: "build", removed_question: "stale" }
    }
    assert_response :redirect

    assert_equal [ "housing" ], response_record.answers.keys
  end

  test "publishing stamps published_at" do
    patch admin_election_candidate_survey_response_path(@candidate), params: {
      warehouse_election_candidate_survey_response: { status: "published", source: "form" },
      answers: { housing: "build" }
    }

    assert response_record.published?
    assert response_record.published_at.present?
  end

  test "a transcribed answer outside the offered options is kept" do
    patch admin_election_candidate_survey_response_path(@candidate), params: {
      warehouse_election_candidate_survey_response: { status: "draft", source: "phone" },
      answers: { housing: "supports with caveats" }
    }

    assert_equal "supports with caveats", response_record.answers["housing"]
  end

  test "re-saving updates the one row rather than adding another" do
    2.times do |i|
      patch admin_election_candidate_survey_response_path(@candidate), params: {
        warehouse_election_candidate_survey_response: { status: "draft", source: "admin" },
        answers: { transit: "Revision #{i}" }
      }
    end

    assert_equal 1, @survey.candidate_responses.count
    assert_equal "Revision 1", response_record.answers["transit"]
  end

  test "clearing removes the response" do
    patch admin_election_candidate_survey_response_path(@candidate), params: {
      warehouse_election_candidate_survey_response: { status: "draft", source: "admin" },
      answers: { housing: "build" }
    }
    assert response_record.present?

    delete admin_election_candidate_survey_response_path(@candidate)
    assert_nil response_record
  end

  test "an election with no candidate questionnaire redirects instead of erroring" do
    @survey.destroy!

    get edit_admin_election_candidate_survey_response_path(@candidate)
    assert_redirected_to admin_election_path(@election)
  end

  test "the entry form requires an admin" do
    # A fresh session with no sign-in — the only write path for candidate
    # answers must not be reachable unauthenticated.
    reset!

    get edit_admin_election_candidate_survey_response_path(@candidate)
    assert_response :redirect
  end
end
