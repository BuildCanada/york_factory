require "test_helper"
require "rake"

# The seed is how every environment other than a laptop gets the questionnaire,
# so what matters is that it rebuilds from nothing and that re-running it is
# safe — including on a response staff have already reviewed and published.
class ElectionsSeedTest < ActiveSupport::TestCase
  COMMITTED_RESPONSES = Rails.root.join(
    "db/seeds/elections/responses/toronto_2026_candidate_responses.json"
  ).freeze
  COMMITTED_QUESTIONS = Rails.root.join(
    "db/seeds/elections/toronto_2026_candidate_questionnaire.json"
  ).freeze

  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("elections:seed_candidate_responses")

    jurisdiction = Warehouse::Jurisdiction.find_or_create_by!(slug: "toronto") do |j|
      j.name = "City of Toronto"
      j.code = "TOR-ON"
      j.level = "municipal"
      j.fiscal_year_start_month = 1
      j.default_currency = "CAD"
    end
    @election = Warehouse::Election.create!(
      jurisdiction: jurisdiction, slug: "seedtown-2026", name: "Seedtown 2026",
      kind: "municipal", election_date: Date.new(2026, 10, 26), published_at: 1.day.ago
    )
    @race = @election.races.create!(
      office_type: "councillor", district_type: "ward", district_number: 7
    )
    @candidate = Warehouse::ElectionCandidate.create!(
      race: @race, full_name: "Ward, Nicki", first_name: "Nicki", last_name: "Ward",
      status: "active"
    )
    @survey = @election.surveys.create!(
      slug: "candidate-questionnaire", audience: "candidate", version: "1",
      published_at: 1.day.ago
    )
    @survey.questions.create!(
      question_id: "housing_as_of_right", step_id: "housing", step_title: "Housing",
      step_position: 0, position: 0, question_type: "radio", label: "As of right?",
      options: [ { "value" => "yes", "label" => "Yes" } ]
    )
  end

  def write_seed(responses, path: Rails.root.join("tmp/test_candidate_responses.json"))
    File.write(path, JSON.pretty_generate(
      "election_slug" => "seedtown-2026",
      "survey_slug" => "candidate-questionnaire",
      "survey_version" => "1",
      "source" => "form",
      "responses" => responses
    ))
    path
  end

  def one_response(overrides = {})
    {
      "candidate" => { "full_name" => "Ward, Nicki", "office_type" => "councillor",
                       "district_number" => 7 },
      "submitted_at" => "2026-09-04T15:28:46Z",
      "answers" => { "housing_as_of_right" => "yes" },
      "explanations" => { "housing_as_of_right" => "Everywhere." }
    }.merge(overrides)
  end

  def seed(path, publish: false)
    CandidateResponseSeed.new(path: path, publish: publish).run
  end

  test "loads a response onto the matching candidate" do
    out, = capture_io { seed(write_seed([ one_response ])) }

    assert_match(/1 loaded, 0 refreshed/, out)
    record = @survey.candidate_responses.sole
    assert_equal @candidate, record.candidate
    assert_equal({ "housing_as_of_right" => "yes" }, record.answers)
    assert_equal({ "housing_as_of_right" => "Everywhere." }, record.explanations)
    assert_equal Time.utc(2026, 9, 4, 15, 28, 46), record.submitted_at
  end

  # Answers are attributed public statements; the seed is not a decision to
  # release them.
  test "responses land as drafts by default" do
    capture_io { seed(write_seed([ one_response ])) }

    assert_predicate @survey.candidate_responses.sole, :draft?
    assert_nil @survey.candidate_responses.sole.published_at
  end

  test "PUBLISH publishes newly loaded responses" do
    capture_io { seed(write_seed([ one_response ]), publish: true) }

    record = @survey.candidate_responses.sole
    assert_predicate record, :published?
    assert_not_nil record.published_at
  end

  # The whole point of a committed seed is that you re-run it when the sheet
  # changes, so it must not undo a review that already happened.
  test "re-seeding refreshes answers without touching a published response" do
    capture_io { seed(write_seed([ one_response ]), publish: true) }
    published_at = @survey.candidate_responses.sole.published_at

    refreshed = one_response("answers" => { "housing_as_of_right" => "no" })
    out, = capture_io { seed(write_seed([ refreshed ])) }

    assert_match(/0 loaded, 1 refreshed/, out)
    record = @survey.candidate_responses.sole
    assert_equal({ "housing_as_of_right" => "no" }, record.answers)
    assert_predicate record, :published?, "a re-seed must not un-publish a reviewed response"
    assert_equal published_at, record.published_at
  end

  test "re-seeding does not publish a response that was held back" do
    capture_io { seed(write_seed([ one_response ])) }
    capture_io { seed(write_seed([ one_response ]), publish: true) }

    assert_predicate @survey.candidate_responses.sole, :draft?
  end

  # The roster is fed by the candidate pipeline and lags the form, so an
  # unknown name is reported and skipped rather than failing the whole load.
  test "a candidate who is not on the roster is reported, not fatal" do
    rows = [ one_response, one_response("candidate" => {
      "full_name" => "Nobody, Ann", "office_type" => "councillor", "district_number" => 7
    }) ]

    out, = capture_io { seed(write_seed(rows)) }

    assert_match(/1 loaded/, out)
    assert_match(/Not on the roster \(1\)/, out)
    assert_match(/Nobody, Ann/, out)
    assert_equal 1, @survey.candidate_responses.count
  end

  # Matching on name alone would attribute a councillor's positions to a
  # trustee who happens to share it.
  test "a name in another race is not matched" do
    trustee_race = @election.races.create!(
      office_type: "trustee", district_type: "ward", district_number: 7
    )
    Warehouse::ElectionCandidate.create!(
      race: trustee_race, full_name: "Ward, Nicki", status: "active"
    )

    capture_io { seed(write_seed([ one_response ])) }

    assert_equal @candidate, @survey.candidate_responses.sole.candidate
  end

  # A seed file that names a question the survey does not define would be
  # rejected by the model at save time, so guard the committed pair here where
  # the failure is legible instead of at deploy time.
  test "the committed responses only answer questions the committed set defines" do
    questions = JSON.parse(File.read(COMMITTED_QUESTIONS))
      .fetch("questions").map { |q| q.fetch("question_id") }.to_set
    answered = JSON.parse(File.read(COMMITTED_RESPONSES))
      .fetch("responses").flat_map { |r| r.fetch("answers").keys }.uniq

    assert_empty answered - questions.to_a,
      "committed answers reference question ids the committed question set does not define"
  end

  test "the committed seed carries no contact details" do
    raw = File.read(COMMITTED_RESPONSES)

    assert_not_includes raw, "@gmail.com"
    assert_not_includes raw, "email"
  end
end
