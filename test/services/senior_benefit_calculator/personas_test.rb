require "test_helper"

class SeniorBenefitCalculator::PersonasTest < ActiveSupport::TestCase
  test "all returns all personas" do
    personas = SeniorBenefitCalculator::Personas.all
    assert personas.length >= 6
    assert personas.all? { |p| p[:id].present? }
    assert personas.all? { |p| p[:name].present? }
    assert personas.all? { |p| p[:profile].present? }
  end

  test "find returns specific persona" do
    persona = SeniorBenefitCalculator::Personas.find("tfsa_maximizer")
    assert_equal "TFSA Maximizer", persona[:name]
    assert_equal 70, persona[:profile][:age]
  end

  test "find returns nil for unknown persona" do
    assert_nil SeniorBenefitCalculator::Personas.find("nonexistent")
  end

  test "calculate_all returns results for all personas" do
    results = SeniorBenefitCalculator::Personas.calculate_all
    assert results.length >= 6

    results.each do |r|
      assert r[:result].key?(:net_income), "#{r[:name]} should have net_income"
    end
  end

  test "TFSA maximizer gets full benefits under current rules" do
    results = SeniorBenefitCalculator::Personas.calculate_all
    tfsa = results.find { |r| r[:id] == "tfsa_maximizer" }
    median = results.find { |r| r[:id] == "median_canadian_senior" }

    # The injustice: millionaire gets MORE benefits than median senior
    assert tfsa[:result][:total_benefits] > median[:result][:total_benefits],
      "TFSA maximizer (#{tfsa[:result][:total_benefits]}) should get more benefits than median senior (#{median[:result][:total_benefits]}) under current rules"
  end

  test "policy overrides affect persona calculations" do
    current = SeniorBenefitCalculator::Personas.calculate_all
    reformed = SeniorBenefitCalculator::Personas.calculate_all(include_tfsa_in_gis: true)

    tfsa_current = current.find { |r| r[:id] == "tfsa_maximizer" }
    tfsa_reformed = reformed.find { |r| r[:id] == "tfsa_maximizer" }

    assert tfsa_reformed[:result][:gis_benefit] < tfsa_current[:result][:gis_benefit],
      "Including TFSA in GIS should reduce TFSA maximizer's GIS"
  end
end
