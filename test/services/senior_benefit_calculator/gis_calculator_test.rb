require "test_helper"

class SeniorBenefitCalculator::GisCalculatorTest < ActiveSupport::TestCase
  setup do
    @policy = SeniorBenefitCalculator::PolicyParams.new
    @calc = SeniorBenefitCalculator::GisCalculator.new(policy: @policy)
  end

  test "full GIS with zero income" do
    result = @calc.calculate(marital_status: "single", income_excluding_oas: 0)
    expected = 1086.88 * 12
    assert_in_delta expected, result[:gis_net_annual], 0.01
  end

  test "coupled rate is lower" do
    result = @calc.calculate(marital_status: "coupled", income_excluding_oas: 0)
    expected = 654.23 * 12
    assert_in_delta expected, result[:gis_net_annual], 0.01
  end

  test "current regime reduces at 50 cents per dollar" do
    income = 10_000
    result = @calc.calculate(marital_status: "single", income_excluding_oas: income)
    expected_reduction = 10_000 * 0.5
    assert_in_delta expected_reduction, result[:gis_reduction], 0.01
  end

  test "GIS goes to zero at income threshold" do
    result = @calc.calculate(marital_status: "single", income_excluding_oas: 21_624)
    assert_equal 0.0, result[:gis_net_annual]
  end

  test "employment exemption: first $5K fully exempt" do
    result_no_work = @calc.calculate(marital_status: "single", income_excluding_oas: 0)
    result_work = @calc.calculate(marital_status: "single", income_excluding_oas: 5_000, employment_income: 5_000)
    # $5K employment should be fully exempt — same GIS as zero income
    assert_in_delta result_no_work[:gis_net_annual], result_work[:gis_net_annual], 0.01
  end

  test "employment partial exemption: 25% on next $10K" do
    # $12K employment: $5K exempt, $7K at 25% partial = $5,250 assessable
    result = @calc.calculate(marital_status: "single", income_excluding_oas: 12_000, employment_income: 12_000)
    # Assessable employment = $7K * 0.75 = $5,250
    expected_reduction = 5_250 * 0.5
    assert_in_delta expected_reduction, result[:gis_reduction], 0.01
  end

  test "ccb-style regime has lower reduction" do
    policy = SeniorBenefitCalculator::PolicyParams.new(
      gis_clawback_regime: "ccb_style",
      gis_ccb_lower_threshold: 5_000,
      gis_ccb_upper_threshold: 40_000,
      gis_ccb_lower_rate: 0.10,
      gis_ccb_upper_rate: 0.05
    )
    calc = SeniorBenefitCalculator::GisCalculator.new(policy: policy)

    income = 15_000
    result_ccb = calc.calculate(marital_status: "single", income_excluding_oas: income)
    result_current = @calc.calculate(marital_status: "single", income_excluding_oas: income)

    # CCB-style should have lower reduction than current 50%
    assert result_ccb[:gis_reduction] < result_current[:gis_reduction],
      "CCB-style reduction (#{result_ccb[:gis_reduction]}) should be less than current (#{result_current[:gis_reduction]})"
  end

  test "ccb-style: no reduction below lower threshold" do
    policy = SeniorBenefitCalculator::PolicyParams.new(
      gis_clawback_regime: "ccb_style",
      gis_ccb_lower_threshold: 5_000
    )
    calc = SeniorBenefitCalculator::GisCalculator.new(policy: policy)

    result = calc.calculate(marital_status: "single", income_excluding_oas: 4_000)
    assert_equal 0.0, result[:gis_reduction]
  end

  test "TFSA income included when policy enables it" do
    policy = SeniorBenefitCalculator::PolicyParams.new(include_tfsa_in_gis: true)
    calc = SeniorBenefitCalculator::GisCalculator.new(policy: policy)

    result_with_tfsa = calc.calculate(
      marital_status: "single", income_excluding_oas: 0,
      tfsa_withdrawals: 20_000
    )
    result_without = @calc.calculate(
      marital_status: "single", income_excluding_oas: 0,
      tfsa_withdrawals: 20_000
    )

    assert result_with_tfsa[:gis_net_annual] < result_without[:gis_net_annual],
      "Including TFSA should reduce GIS"
  end
end
