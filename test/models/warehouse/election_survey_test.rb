require "test_helper"

class Warehouse::ElectionSurveyTest < ActiveSupport::TestCase
  def jurisdiction
    Warehouse::Jurisdiction.find_or_create_by!(slug: "survey-test-city") do |j|
      j.name = "Survey Test City"
      j.code = "SVY-ON"
      j.level = "municipal"
      j.fiscal_year_start_month = 1
      j.default_currency = "CAD"
    end
  end

  def election
    @election ||= Warehouse::Election.find_or_create_by!(slug: "survey-test-2026") do |e|
      e.jurisdiction = jurisdiction
      e.name = "Survey Test 2026"
      e.kind = "municipal"
      e.election_date = Date.new(2026, 10, 26)
    end
  end

  def survey(slug: "city-priorities", audience: "resident", published: true)
    election.surveys.create!(
      slug: slug,
      audience: audience,
      version: "1",
      published_at: published ? Time.current : nil
    )
  end

  def question(survey, question_id:, step: "one", step_position: 0, position: 0, **attrs)
    survey.questions.create!({
      question_id: question_id,
      step_id: step,
      step_title: step.titleize,
      step_position: step_position,
      position: position,
      question_type: "text",
      label: "Question #{question_id}"
    }.merge(attrs))
  end

  test "slug is unique per election but reusable across elections" do
    survey(slug: "city-priorities")

    duplicate = election.surveys.build(slug: "city-priorities", audience: "resident", version: "1")
    assert duplicate.invalid?
    assert duplicate.errors[:slug].any?

    other = Warehouse::Election.create!(
      jurisdiction: jurisdiction, slug: "survey-test-2030",
      name: "Survey Test 2030", kind: "municipal", election_date: Date.new(2030, 10, 26)
    )
    assert other.surveys.build(slug: "city-priorities", audience: "resident", version: "1").valid?
  end

  test "a slug with uppercase or spaces is rejected" do
    assert election.surveys.build(slug: "City Priorities", audience: "resident", version: "1").invalid?
  end

  test "published scope excludes surveys with no published_at" do
    live = survey(slug: "live")
    survey(slug: "draft", published: false)

    assert_equal [ live.slug ], election.surveys.published.map(&:slug)
  end

  test "steps groups questions by step in step then question order" do
    s = survey
    # Created out of order on purpose — ordering must come from the columns.
    question(s, question_id: "second_step_q", step: "two", step_position: 1, position: 0)
    question(s, question_id: "first_step_b", step: "one", step_position: 0, position: 1)
    question(s, question_id: "first_step_a", step: "one", step_position: 0, position: 0)

    steps = s.reload.steps

    assert_equal %w[one two], steps.map { |st| st[:id] }
    assert_equal %w[first_step_a first_step_b], steps.first[:questions].map { |q| q[:id] }
    assert_equal %w[second_step_q], steps.last[:questions].map { |q| q[:id] }
  end

  test "steps omits a null step intro rather than sending it" do
    s = survey
    question(s, question_id: "q1")

    assert_not steps_for(s).first.key?(:intro)
  end

  test "steps carries the step intro when one is set" do
    s = survey
    question(s, question_id: "q1", step_intro: "Some context.")

    assert_equal "Some context.", steps_for(s).first[:intro]
  end

  test "ward-sourced options are resolved from the passed ward list" do
    s = survey
    question(s, question_id: "ward", question_type: "select", options_source: "wards")

    ward_options = [ { "value" => "ward-1", "label" => "1 — Riverside" } ]
    rendered = s.reload.steps(ward_options: ward_options).first[:questions].first

    assert_equal [ "ward-1", "unsure" ], rendered[:options].map { |o| o["value"] }
  end

  test "meta must be an object" do
    s = survey
    s.meta = [ "not", "a", "hash" ]
    assert s.invalid?
    assert s.errors[:meta].any?
  end

  private

  def steps_for(survey)
    survey.reload.steps
  end
end
