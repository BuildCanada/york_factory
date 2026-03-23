require "test_helper"

class Api::V1::BusinessEstablishmentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @on_biz = BusinessEstablishment.create!(
      business_name: "Ontario Tech Inc", trade_name: "OTI",
      business_number: "123456789RC0001", naics_code: "541510",
      naics_description: "Computer Systems Design", province: "ON",
      city: "Toronto", postal_code: "M5V 1A1"
    )
    @bc_biz = BusinessEstablishment.create!(
      business_name: "BC Restaurant", naics_code: "722511",
      province: "BC", city: "Vancouver"
    )
  end

  test "index returns all establishments" do
    get api_v1_business_establishments_url
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal 2, data.size
  end

  test "index filters by province" do
    get api_v1_business_establishments_url, params: { province: "ON" }
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal 1, data.size
    assert_equal "Ontario Tech Inc", data.first["business_name"]
  end

  test "index filters by NAICS code" do
    get api_v1_business_establishments_url, params: { naics: "541510" }
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal 1, data.size
  end

  test "index filters by name search" do
    get api_v1_business_establishments_url, params: { name: "Restaurant" }
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal 1, data.size
    assert_equal "BC Restaurant", data.first["business_name"]
  end

  test "show returns establishment with linked corporate entity" do
    get api_v1_business_establishment_url(@on_biz)
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal "Ontario Tech Inc", data["business_establishment"]["business_name"]
    assert_nil data["corporate_entity"]
  end
end
