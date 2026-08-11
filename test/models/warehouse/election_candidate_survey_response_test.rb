require "test_helper"

class Warehouse::ElectionCandidateSurveyResponseTest < ActiveSupport::TestCase
  def jurisdiction(slug, name, code)
    Warehouse::Jurisdiction.find_or_create_by!(slug: slug) do |j|
      j.name = name
      j.code = code
      j.level = "municipal"
      j.fiscal_year_start_month = 1
      j.default_currency = "CAD"
    end
  end

  def election_for(slug, name, code)
    Warehouse::Election.find_or_create_by!(slug: "#{slug}-2026") do |e|
      e.jurisdiction = jurisdiction(slug, name, code)
      e.name = "#{name} 2026"
      e.kind = "municipal"
      e.election_date = Date.new(2026, 10, 26)
    end
  end

  def candidate_in(election, name:, ward: 1)
    race = election.races.find_or_create_by!(
      office_type: "councillor", district_type: "ward", district_number: ward
    ) { |r| r.district_name = "Ward #{ward}" }
    race.candidates.find_or_create_by!(full_name: name) { |c| c.status = "active" }
  end

  setup do
    @election = election_for("cand-survey", "Candidate Survey City", "CSC-ON")
    @survey = @election.surveys.create!(
      slug: "candidate-questionnaire", audience: "candidate", version: "1"
    )
    @survey.questions.create!(
      question_id: "housing", step_id: "policy", step_title: "Policy",
      question_type: "radio", label: "Housing?",
      options: [ { "value" => "yes_build", "label" => "Build more" } ]
    )
    @candidate = candidate_in(@election, name: "Casey Candidate")
  end

  def response(**attrs)
    Warehouse::ElectionCandidateSurveyResponse.new(
      { survey: @survey, candidate: @candidate, answers: { "housing" => "yes_build" } }.merge(attrs)
    )
  end

  test "a well-formed response is valid and defaults to an admin-entered draft" do
    r = response
    assert r.valid?, r.errors.full_messages.join(", ")
    assert r.draft?
    assert r.via_admin?
  end

  test "one response per candidate per survey" do
    response.save!
    assert response.invalid?
  end

  test "an answer keyed to a question not in the survey is rejected" do
    r = response(answers: { "housing" => "yes_build", "not_a_question" => "x" })
    assert r.invalid?
    assert_match "not_a_question", r.errors[:answers].join
  end

  test "an explanation keyed to an unknown question is rejected too" do
    r = response(explanations: { "nope" => "because" })
    assert r.invalid?
  end

  test "an answer value outside the offered options is accepted" do
    # Staff transcribe what candidates actually say, which is not always one of
    # the options — refusing it would mean losing the response or the nuance.
    assert response(answers: { "housing" => "supports with caveats" }).valid?
  end

  test "a non-string answer is rejected" do
    assert response(answers: { "housing" => 1 }).invalid?
  end

  test "an over-long answer is rejected" do
    assert response(answers: { "housing" => "x" * 2_001 }).invalid?
  end

  test "publishing stamps published_at when the caller did not" do
    r = response(status: "published")
    assert r.valid?
    assert r.published_at.present?
  end

  test "a candidate standing in another election is rejected" do
    other = election_for("other-city", "Other City", "OTH-ON")
    foreign = candidate_in(other, name: "Foreign Candidate")

    r = response(candidate: foreign)
    assert r.invalid?
    assert r.errors[:candidate].any?
  end

  test "published scope only returns published rows" do
    response(status: "published").save!
    assert_equal 1, @survey.candidate_responses.published.count

    other_candidate = candidate_in(@election, name: "Draft Candidate", ward: 2)
    response(candidate: other_candidate).save!
    assert_equal 1, @survey.candidate_responses.published.count
    assert_equal 2, @survey.candidate_responses.count
  end

  test "tally_answers counts by answer value" do
    response(status: "published").save!
    second = candidate_in(@election, name: "Second Candidate", ward: 2)
    response(candidate: second, answers: { "housing" => "yes_build" }).save!

    assert_equal({ "yes_build" => 2 }, @survey.candidate_responses.tally_answers("housing"))
  end

  test "unanswered_question_ids reports what the candidate skipped" do
    @survey.questions.create!(
      question_id: "transit", step_id: "policy", step_title: "Policy",
      question_type: "yesno", label: "Transit?", position: 1
    )
    r = response
    assert_equal [ "transit" ], r.unanswered_question_ids
  end
end
