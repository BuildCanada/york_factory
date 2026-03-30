require "test_helper"

class Api::V1::SeniorBenefitsControllerTest < ActionDispatch::IntegrationTest
  test "calculate returns benefit breakdown" do
    post api_v1_senior_benefits_calculate_path, params: {
      age: 70, marital_status: "single", years_in_canada: 40,
      pension_income: 10_000
    }, as: :json

    assert_response :success
    json = JSON.parse(response.body)
    assert json["summary"]["net_income"] > 0
    assert json["oas"]["oas_net_annual"] > 0
    assert json["gis"]["gis_net_annual"] > 0
  end

  test "marginal_rates returns sweep data" do
    post api_v1_senior_benefits_marginal_rates_path, params: {
      age: 70, marital_status: "single", years_in_canada: 40
    }, as: :json

    assert_response :success
    json = JSON.parse(response.body)
    assert json["data"].length > 100
    assert_equal 0, json["data"].first["income"]
  end

  test "compare returns current vs proposed" do
    post api_v1_senior_benefits_compare_path, params: {
      age: 70, marital_status: "single", years_in_canada: 40,
      pension_income: 10_000,
      proposed_policy: { gis_clawback_regime: "ccb_style" }
    }, as: :json

    assert_response :success
    json = JSON.parse(response.body)
    assert json.key?("current")
    assert json.key?("proposed")
    assert json.key?("difference")
  end

  test "project returns demographic projections" do
    post api_v1_senior_benefits_project_path, as: :json

    assert_response :success
    json = JSON.parse(response.body)
    assert json["projections"].length == 26
    assert json["assumptions"].key?("inflation_rate")
  end

  test "personas returns all personas" do
    get api_v1_senior_benefits_personas_path

    assert_response :success
    json = JSON.parse(response.body)
    assert json.length >= 6
    assert json.first.key?("name")
  end

  test "personas with calculate returns results" do
    get api_v1_senior_benefits_personas_path, params: { calculate: "true" }

    assert_response :success
    json = JSON.parse(response.body)
    assert json.first.key?("result")
    assert json.first["result"].key?("net_income")
  end

  test "calculate with policy overrides" do
    post api_v1_senior_benefits_calculate_path, params: {
      age: 70, marital_status: "single", years_in_canada: 40,
      tfsa_withdrawals: 85_000,
      policy: { include_tfsa_in_gis: true }
    }, as: :json

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal 0.0, json["gis"]["gis_net_annual"]
  end
end
