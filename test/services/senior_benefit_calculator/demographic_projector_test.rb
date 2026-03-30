require "test_helper"

class SeniorBenefitCalculator::DemographicProjectorTest < ActiveSupport::TestCase
  test "projects from 2025 to 2050" do
    projector = SeniorBenefitCalculator::DemographicProjector.new
    result = projector.project

    assert_equal 2025, result[:projections].first[:year]
    assert_equal 2050, result[:projections].last[:year]
    assert_equal 26, result[:projections].length
  end

  test "costs increase over time" do
    projector = SeniorBenefitCalculator::DemographicProjector.new
    result = projector.project

    first = result[:projections].first[:total_cost_billions]
    last = result[:projections].last[:total_cost_billions]

    assert last > first, "Costs should increase from #{first}B to #{last}B"
  end

  test "worker to retiree ratio declines" do
    projector = SeniorBenefitCalculator::DemographicProjector.new
    result = projector.project

    first_ratio = result[:projections].first[:worker_to_retiree_ratio]
    last_ratio = result[:projections].last[:worker_to_retiree_ratio]

    assert last_ratio < first_ratio, "Worker-retiree ratio should decline"
    assert_in_delta 3.5, first_ratio, 0.01
    assert_in_delta 2.3, last_ratio, 0.01
  end

  test "cost per worker increases" do
    projector = SeniorBenefitCalculator::DemographicProjector.new
    result = projector.project

    first_cost = result[:projections].first[:cost_per_working_canadian]
    last_cost = result[:projections].last[:cost_per_working_canadian]

    assert last_cost > first_cost, "Cost per worker should increase"
  end

  test "includes assumptions in output" do
    projector = SeniorBenefitCalculator::DemographicProjector.new
    result = projector.project

    assert result[:assumptions].key?(:inflation_rate)
    assert result[:assumptions].key?(:population_growth_65_plus_rate)
    assert result[:assumptions].key?(:base_oas_cost_billions)
  end

  test "custom inflation rate changes projections" do
    low = SeniorBenefitCalculator::DemographicProjector.new(inflation_rate: 0.01)
    high = SeniorBenefitCalculator::DemographicProjector.new(inflation_rate: 0.05)

    low_2050 = low.project[:projections].last[:total_cost_billions]
    high_2050 = high.project[:projections].last[:total_cost_billions]

    assert high_2050 > low_2050, "Higher inflation should mean higher costs"
  end
end
