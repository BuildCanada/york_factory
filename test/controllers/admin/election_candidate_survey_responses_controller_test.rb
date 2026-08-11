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

  test "a stored custom answer survives an unrelated edit" do
    # A transcribed answer outside the offered options is a published statement.
    # Editing a different question must not delete it.
    patch admin_election_candidate_survey_response_path(@candidate), params: {
      warehouse_election_candidate_survey_response: { status: "published", source: "phone" },
      answers: { housing: "supports with caveats" }
    }
    assert_equal "supports with caveats", response_record.answers["housing"]

    # Re-open the form and save it back the way a staff member would: the browser
    # posts whatever the rendered form contains.
    get edit_admin_election_candidate_survey_response_path(@candidate)
    assert_response :success
    posted = form_answers_from_response

    patch admin_election_candidate_survey_response_path(@candidate), params: {
      warehouse_election_candidate_survey_response: { status: "published", source: "phone" },
      answers: posted.merge("transit" => "Added later.")
    }

    assert_equal "supports with caveats", response_record.answers["housing"],
      "the transcribed answer was lost by an ordinary re-save"
  end


  test "a transcribed answer can still be cleared deliberately" do
    patch admin_election_candidate_survey_response_path(@candidate), params: {
      warehouse_election_candidate_survey_response: { status: "draft", source: "phone" },
      answers: { housing: "supports with caveats" }
    }
    assert_equal "supports with caveats", response_record.answers["housing"]

    # Picking "— no response —" posts a blank, which must still clear it: the
    # round-trip fix must not make a transcribed answer permanent.
    patch admin_election_candidate_survey_response_path(@candidate), params: {
      warehouse_election_candidate_survey_response: { status: "draft", source: "phone" },
      answers: { housing: "" }
    }

    assert_nil response_record.answers["housing"]
  end

  test "the form offers a transcribed answer as its own selected choice" do
    patch admin_election_candidate_survey_response_path(@candidate), params: {
      warehouse_election_candidate_survey_response: { status: "draft", source: "phone" },
      answers: { housing: "supports with caveats" }
    }

    get edit_admin_election_candidate_survey_response_path(@candidate)
    assert_select "select[name='answers[housing]'] option[selected][value=?]", "supports with caveats"
  end

  # What the rendered form would actually submit for each answer field.
  def form_answers_from_response
    doc = Nokogiri::HTML(response.body)
    doc.css("[name^='answers[']").each_with_object({}) do |field, acc|
      qid = field["name"][/answers\[(.+)\]/, 1]
      acc[qid] = if field.name == "select"
        field.at_css("option[selected]")&.[]("value").to_s
      else
        field["value"].to_s
      end
    end
  end
end
