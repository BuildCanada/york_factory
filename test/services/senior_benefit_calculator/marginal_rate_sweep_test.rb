require "test_helper"

class SeniorBenefitCalculator::MarginalRateSweepTest < ActiveSupport::TestCase
  test "sweep returns data points from 0 to 200K" do
    sweep = SeniorBenefitCalculator::MarginalRateSweep.new
    points = sweep.sweep(age: 70, marital_status: "single", years_in_canada: 40)

    assert_equal 0, points.first[:income]
    assert_equal 200_000, points.last[:income]
    assert points.length > 100, "Should have many data points"
  end

  test "each point has required fields" do
    sweep = SeniorBenefitCalculator::MarginalRateSweep.new
    points = sweep.sweep(age: 70, marital_status: "single", years_in_canada: 40)

    point = points[10]
    assert point.key?(:income)
    assert point.key?(:net_income)
    assert point.key?(:oas)
    assert point.key?(:gis)
    assert point.key?(:federal_tax)
    assert point.key?(:emtr)
  end

  test "EMTR is high in GIS clawback zone" do
    sweep = SeniorBenefitCalculator::MarginalRateSweep.new
    points = sweep.sweep(age: 70, marital_status: "single", years_in_canada: 40)

    # Find EMTR around $10K income (deep in GIS clawback)
    point = points.find { |p| p[:income] == 10_000 }
    assert point[:emtr] > 0.5, "EMTR should exceed 50% in GIS clawback zone (was #{point[:emtr]})"
  end

  test "CCB-style regime has lower EMTR" do
    current_sweep = SeniorBenefitCalculator::MarginalRateSweep.new
    ccb_sweep = SeniorBenefitCalculator::MarginalRateSweep.new(
      gis_clawback_regime: "ccb_style",
      gis_ccb_lower_rate: 0.10,
      gis_ccb_upper_rate: 0.05
    )

    profile = { age: 70, marital_status: "single", years_in_canada: 40 }
    current_points = current_sweep.sweep(profile)
    ccb_points = ccb_sweep.sweep(profile)

    # Average EMTR in $5K-$20K range should be lower for CCB
    current_avg = current_points.select { |p| p[:income].between?(5_000, 20_000) }.map { |p| p[:emtr] }.sum / 31.0
    ccb_avg = ccb_points.select { |p| p[:income].between?(5_000, 20_000) }.map { |p| p[:emtr] }.sum / 31.0

    assert ccb_avg < current_avg,
      "CCB average EMTR (#{ccb_avg.round(3)}) should be lower than current (#{current_avg.round(3)})"
  end

  test "EMTR values are between 0 and 1" do
    sweep = SeniorBenefitCalculator::MarginalRateSweep.new
    points = sweep.sweep(age: 70, marital_status: "single", years_in_canada: 40)

    points.each do |point|
      assert point[:emtr] >= 0 && point[:emtr] <= 1,
        "EMTR at income #{point[:income]} should be 0-1, was #{point[:emtr]}"
    end
  end
end
