require "test_helper"

class Api::V1::CorporateEntitiesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @federal = CorporateEntity.create!(
      jurisdiction: "federal", registry_id: "F001",
      legal_name: "Federal Test Corp", status: "Active",
      corporation_type: "CBCA", registered_office_province: "ON"
    )
    @bc = CorporateEntity.create!(
      jurisdiction: "bc", registry_id: "BC001",
      legal_name: "BC Test Corp", status: "Active",
      registered_office_province: "BC"
    )
  end

  test "index returns all entities" do
    get api_v1_corporate_entities_url
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal 2, data.size
  end

  test "index filters by jurisdiction" do
    get api_v1_corporate_entities_url, params: { jurisdiction: "federal" }
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal 1, data.size
    assert_equal "Federal Test Corp", data.first["legal_name"]
  end

  test "index filters by province" do
    get api_v1_corporate_entities_url, params: { province: "BC" }
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal 1, data.size
    assert_equal "BC Test Corp", data.first["legal_name"]
  end

  test "index filters by name search" do
    get api_v1_corporate_entities_url, params: { name: "Federal" }
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal 1, data.size
  end

  test "show returns entity with associations" do
    get api_v1_corporate_entity_url(@federal)
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal "Federal Test Corp", data["corporate_entity"]["legal_name"]
    assert_kind_of Array, data["aliases"]
    assert_kind_of Array, data["registrations"]
  end

  test "directors returns director appointments" do
    director = CorporateDirector.create!(
      full_name: "Jane Director", normalized_name: "jane director"
    )
    DirectorAppointment.create!(
      corporate_entity: @federal, corporate_director: director,
      appointed_date: Date.new(2020, 1, 1), role: "Director"
    )

    get directors_api_v1_corporate_entity_url(@federal)
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal 1, data["directors"].size
    assert_equal "Jane Director", data["directors"].first["director"]["full_name"]
  end
end
