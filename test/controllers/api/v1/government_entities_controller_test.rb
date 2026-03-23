require "test_helper"

class Api::V1::GovernmentEntitiesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @entity = GovernmentEntity.create!(canonical_name: "Department of Finance")
    GovernmentEntity.create!(canonical_name: "Department of Defence")
  end

  test "index returns all government entities" do
    get api_v1_government_entities_url
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal 2, data.size
  end

  test "show returns entity details" do
    get api_v1_government_entity_url(@entity)
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal "Department of Finance", data["government_entity"]["canonical_name"]
  end
end
