require "test_helper"

class SeniorBenefitCalculator::BenefitStackTest < ActiveSupport::TestCase
  test "median senior gets OAS + GIS + age credit" do
    stack = SeniorBenefitCalculator::BenefitStack.new
    result = stack.calculate(
      age: 69, marital_status: "single", years_in_canada: 40,
      employment_income: 5_000, pension_income: 9_800
    )

    assert result[:summary][:oas_benefit] > 0, "Should receive OAS"
    assert result[:summary][:gis_benefit] > 0, "Should receive GIS"
    assert result[:age_credit][:age_credit_value] > 0, "Should receive age credit"
    assert result[:summary][:net_income] > 0, "Net income should be positive"
  end

  test "high income senior gets no GIS" do
    stack = SeniorBenefitCalculator::BenefitStack.new
    result = stack.calculate(
      age: 70, marital_status: "single", years_in_canada: 40,
      pension_income: 60_000
    )

    assert result[:summary][:oas_benefit] > 0, "Should still get OAS"
    assert_equal 0.0, result[:summary][:gis_benefit], "Should not get GIS"
  end

  test "very high income senior loses OAS to clawback" do
    stack = SeniorBenefitCalculator::BenefitStack.new
    result = stack.calculate(
      age: 70, marital_status: "single", years_in_canada: 40,
      pension_income: 160_000
    )

    assert_equal 0.0, result[:summary][:oas_benefit], "OAS should be fully clawed back"
  end

  test "young person gets nothing" do
    stack = SeniorBenefitCalculator::BenefitStack.new
    result = stack.calculate(
      age: 35, marital_status: "single", years_in_canada: 35,
      employment_income: 59_300
    )

    assert_equal 0.0, result[:summary][:oas_benefit]
    assert_equal 0.0, result[:summary][:gis_benefit]
    assert_equal 0.0, result[:age_credit][:age_credit_value]
  end

  test "TFSA maximizer gets full benefits under current rules" do
    stack = SeniorBenefitCalculator::BenefitStack.new
    result = stack.calculate(
      age: 70, marital_status: "single", years_in_canada: 40,
      tfsa_withdrawals: 85_000, net_worth: 1_200_000
    )

    # Under current rules, TFSA is invisible
    max_oas = 727.67 * 12
    max_gis = 1086.88 * 12
    assert_in_delta max_oas, result[:summary][:oas_benefit], 0.01
    assert_in_delta max_gis, result[:summary][:gis_benefit], 0.01
  end

  test "TFSA maximizer loses GIS when TFSA included" do
    stack = SeniorBenefitCalculator::BenefitStack.new(include_tfsa_in_gis: true)
    result = stack.calculate(
      age: 70, marital_status: "single", years_in_canada: 40,
      tfsa_withdrawals: 85_000, net_worth: 1_200_000
    )

    assert_equal 0.0, result[:summary][:gis_benefit], "GIS should be zero with $85K TFSA income counted"
  end

  test "policy overrides change results" do
    # Double the GIS
    stack = SeniorBenefitCalculator::BenefitStack.new(gis_monthly_single: 2173.76)
    result = stack.calculate(
      age: 70, marital_status: "single", years_in_canada: 40,
      pension_income: 0
    )

    expected = 2173.76 * 12
    assert_in_delta expected, result[:summary][:gis_benefit], 0.01
  end

  test "summary includes all income components" do
    stack = SeniorBenefitCalculator::BenefitStack.new
    result = stack.calculate(
      age: 70, marital_status: "single", years_in_canada: 40,
      employment_income: 3_000, pension_income: 8_000, investment_income: 1_000
    )

    summary = result[:summary]
    assert_equal 3_000.0, summary[:employment_income]
    assert_equal 8_000.0, summary[:pension_income]
    assert_equal 1_000.0, summary[:investment_income]
    assert_equal 12_000.0, summary[:total_market_income]
    assert summary[:total_gross_income] > summary[:total_market_income]
  end
end
