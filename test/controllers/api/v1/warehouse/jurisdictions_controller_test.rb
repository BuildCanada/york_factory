require "test_helper"

class Api::V1::Warehouse::JurisdictionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    Warehouse::Jurisdiction.find_or_create_by!(code: "AB") do |j|
      j.name = "Alberta"; j.slug = "ab"; j.level = "provincial"; j.fiscal_year_start_month = 4
    end
  end

  test "index returns jurisdictions with name, code, level" do
    get api_v1_warehouse_jurisdictions_url
    assert_response :success
    data = JSON.parse(response.body)["data"]
    ab = data.find { |j| j["code"] == "AB" }
    assert ab
    assert_equal "Alberta", ab["name"]
    assert_equal "provincial", ab["level"]
  end
end
