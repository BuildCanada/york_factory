require "test_helper"

# Exercises the full review workflow: flags, decisions, queue, approve/reject paths.
class Warehouse::ReviewWorkflowTest < ActiveSupport::TestCase
  setup do
    @jur = Warehouse::Jurisdiction.find_or_create_by!(code: "RW-#{SecureRandom.hex(2)}") do |j|
      j.name = "RW"; j.slug = "rw-#{SecureRandom.hex(2)}"
      j.level = "municipal"; j.fiscal_year_start_month = 1; j.default_currency = "CAD"
    end
    @unit = Warehouse::Unit.find_or_create_by!(symbol: "count") { |u| u.kind = "absolute"; u.base_unit = "count"; u.scale = 1.0 }
    @org = Warehouse::Organization.create!(jurisdiction: @jur, slug: "rw-org-#{SecureRandom.hex(2)}", canonical_name: "RW Org")
    @doc = Warehouse::KpiDocument.create!(jurisdiction: @jur, organization: @org, fiscal_year: 2024,
      doc_url: "https://example.com/rw-#{SecureRandom.hex(4)}.pdf")
    @measure = Warehouse::Measure.create!(organization: @org, slug: "rw-m-#{SecureRandom.hex(2)}",
      canonical_name: "RW Measure", unit: @unit)
  end

  def build_obs(value_type: "actual", value: 10, needs_review: false)
    Warehouse::ExtractedObservation.create!(
      measure: @measure, document: @doc, measurement_year: 2024,
      value_type: value_type, value_numeric: value, needs_review: needs_review
    )
  end

  test "approve! creates canonical, resolves open flags, records decision" do
    obs = build_obs
    obs.review_flags.create!(flag_type: "low_confidence", severity: "low", message: "m")
    obs.review_flags.create!(flag_type: "unit_ambiguous", severity: "high", message: "m")

    assert_difference -> { Warehouse::CanonicalObservation.count } => 1,
                       -> { Warehouse::ReviewDecision.count } => 1 do
      obs.approve!(reviewer: "alice", notes: "looks ok")
    end

    obs.reload
    assert_equal "approved", obs.review_status
    assert_equal 0, obs.open_review_flags.count
    assert obs.review_flags.all?(&:resolved_at)

    decision = obs.review_decisions.last
    assert_equal "alice", decision.reviewer
    assert_equal "approved", decision.decision
    assert_equal "looks ok", decision.notes
  end

  test "approve! with new_value applies edits and records edited decision" do
    obs = build_obs(value: 10)
    obs.approve!(reviewer: "alice", new_value: { "value_numeric" => 20 })

    obs.reload
    assert_equal 20.0, obs.value_numeric
    assert_equal "edited", obs.review_decisions.last.decision
    assert_equal({ "value_numeric" => 20 }, obs.review_decisions.last.new_value)
    assert_equal 10.0, obs.review_decisions.last.previous_value["value_numeric"]
    assert_equal 20.0, obs.canonical_observation.value_numeric
  end

  test "reject! flips status, resolves flags, records rejected decision, no canonical" do
    obs = build_obs
    obs.review_flags.create!(flag_type: "unit_ambiguous", severity: "high", message: "m")

    assert_no_difference -> { Warehouse::CanonicalObservation.count } do
      assert_difference -> { Warehouse::ReviewDecision.count } => 1 do
        obs.reject!(reviewer: "bob", notes: "not credible")
      end
    end

    obs.reload
    assert_equal "rejected", obs.review_status
    refute obs.needs_review
    assert_equal 0, obs.open_review_flags.count
    assert_equal "rejected", obs.review_decisions.last.decision
  end

  test "human_review_queue surfaces pending observations with needs_review or open flags" do
    quiet = build_obs(value_type: "actual")            # pending, no flags, needs_review=false → excluded
    needs = build_obs(value_type: "target", needs_review: true)
    flagged = build_obs(value_type: "projected")
    flagged.review_flags.create!(flag_type: "x", severity: "critical", message: "m")
    flagged.review_flags.create!(flag_type: "y", severity: "low", message: "m")

    queue_ids = Warehouse::HumanReviewQueueEntry.pluck(:extracted_observation_id)
    assert_includes queue_ids, needs.id
    assert_includes queue_ids, flagged.id
    refute_includes queue_ids, quiet.id

    flagged_row = Warehouse::HumanReviewQueueEntry.find(flagged.id)
    assert_equal 2, flagged_row.open_flag_count
    assert_equal "critical", flagged_row.highest_open_severity
    assert_equal 4, flagged_row.highest_open_severity_rank
  end

  test "human_review_queue drops rows after approval" do
    obs = build_obs(needs_review: true)
    assert_includes Warehouse::HumanReviewQueueEntry.pluck(:extracted_observation_id), obs.id

    obs.approve!(reviewer: "alice")
    refute_includes Warehouse::HumanReviewQueueEntry.pluck(:extracted_observation_id), obs.id
  end

  test "queue ranks by severity descending" do
    crit = build_obs(value_type: "actual",  needs_review: true)
    low  = build_obs(value_type: "target",  needs_review: true)
    crit.review_flags.create!(flag_type: "x", severity: "critical", message: "m")
    low.review_flags.create!(flag_type: "x", severity: "low",      message: "m")

    ordered = Warehouse::HumanReviewQueueEntry.by_severity
      .where(extracted_observation_id: [ crit.id, low.id ]).pluck(:extracted_observation_id)
    assert_equal [ crit.id, low.id ], ordered
  end
end
