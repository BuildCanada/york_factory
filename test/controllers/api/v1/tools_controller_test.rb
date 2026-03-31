require "test_helper"

class Api::V1::ToolsControllerTest < ActionDispatch::IntegrationTest
  test "index returns published tools" do
    get api_v1_tools_url
    assert_response :success
    data = JSON.parse(response.body)["data"]
    assert data.is_a?(Array)
  end

  test "index excludes draft tools" do
    get api_v1_tools_url
    data = JSON.parse(response.body)["data"]
    ids = data.map { |t| t["id"] }
    assert_not_includes ids, tools(:draft_tool).id
  end

  test "index filters by featured" do
    get api_v1_tools_url, params: { featured: true }
    assert_response :success
    data = JSON.parse(response.body)["data"]
    data.each { |t| assert t["featured"] }
  end

  test "tool serialization includes expected fields" do
    get api_v1_tools_url
    data = JSON.parse(response.body)["data"]
    tool_data = data.first
    assert tool_data.key?("title")
    assert tool_data.key?("url")
    assert tool_data.key?("size")
    assert tool_data.key?("accent_color")
  end
end
