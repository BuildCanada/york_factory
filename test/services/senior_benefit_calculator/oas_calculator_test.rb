require "test_helper"

class SeniorBenefitCalculator::OasCalculatorTest < ActiveSupport::TestCase
  setup do
    @policy = SeniorBenefitCalculator::PolicyParams.new
    @calc = SeniorBenefitCalculator::OasCalculator.new(policy: @policy)
  end

  test "no OAS before eligibility age" do
    result = @calc.calculate(age: 64, years_in_canada: 40, net_income: 0)
    assert_equal 0.0, result[:oas_net_annual]
  end

  test "full OAS at 65 with 40 years residence" do
    result = @calc.calculate(age: 65, years_in_canada: 40, net_income: 0)
    expected = 727.67 * 12
    assert_in_delta expected, result[:oas_gross_annual], 0.01
    assert_equal 0.0, result[:oas_recovery_tax]
    assert_in_delta expected, result[:oas_net_annual], 0.01
  end

  test "enhanced OAS for 75+" do
    result = @calc.calculate(age: 76, years_in_canada: 40, net_income: 0)
    expected = 800.44 * 12
    assert_in_delta expected, result[:oas_gross_annual], 0.01
  end

  test "partial pension with 20 years residence" do
    result = @calc.calculate(age: 70, years_in_canada: 20, net_income: 0)
    assert_in_delta 0.5, result[:residence_fraction], 0.01
    assert_in_delta 727.67 * 12 * 0.5, result[:oas_gross_annual], 0.01
  end

  test "no pension with less than 10 years residence" do
    result = @calc.calculate(age: 70, years_in_canada: 9, net_income: 0)
    assert_equal 0.0, result[:oas_net_annual]
  end

  test "recovery tax claws back OAS above threshold" do
    income = 100_997 # $10K above threshold
    result = @calc.calculate(age: 70, years_in_canada: 40, net_income: income)
    expected_tax = 10_000 * 0.15
    assert_in_delta expected_tax, result[:oas_recovery_tax], 0.01
  end

  test "recovery tax cannot exceed gross OAS" do
    result = @calc.calculate(age: 70, years_in_canada: 40, net_income: 200_000)
    gross = 727.67 * 12
    assert_in_delta gross, result[:oas_recovery_tax], 0.01
    assert_equal 0.0, result[:oas_net_annual]
  end

  test "wealth test reduces OAS when enabled" do
    policy = SeniorBenefitCalculator::PolicyParams.new(
      wealth_test_enabled: true,
      wealth_test_threshold: 1_000_000,
      wealth_test_home_exemption: 500_000,
      wealth_test_reduction_rate: 0.15
    )
    calc = SeniorBenefitCalculator::OasCalculator.new(policy: policy)

    # $2M net worth, $600K home (only $500K exempt), so assessable = $2M - $500K = $1.5M
    # Excess over threshold = $500K, deemed income = $500K * 0.15 = $75K
    # OAS reduction = $75K * 0.15 = $11,250
    result = calc.calculate(age: 70, years_in_canada: 40, net_income: 0, net_worth: 2_000_000, home_value: 600_000)
    assert result[:oas_wealth_reduction] > 0
    assert result[:oas_net_annual] < 727.67 * 12
  end

  test "wealth test does not apply when disabled" do
    result = @calc.calculate(age: 70, years_in_canada: 40, net_income: 0, net_worth: 10_000_000, home_value: 0)
    assert_equal 0.0, result[:oas_wealth_reduction]
  end
end
