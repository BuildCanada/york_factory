require "test_helper"

class Api::V1::TestimonialsControllerTest < ActionDispatch::IntegrationTest
  test "index returns published testimonials ordered by position" do
    get api_v1_testimonials_url
    assert_response :success
    data = JSON.parse(response.body)["data"]
    assert data.is_a?(Array)
    positions = data.map { |t| t["position"] }
    assert_equal positions, positions.sort
  end

  test "index excludes draft testimonials" do
    get api_v1_testimonials_url
    data = JSON.parse(response.body)["data"]
    ids = data.map { |t| t["id"] }
    assert_not_includes ids, testimonials(:draft_testimonial).id
  end

  test "testimonial serialization includes expected fields" do
    get api_v1_testimonials_url
    data = JSON.parse(response.body)["data"]
    t = data.first
    assert t.key?("name")
    assert t.key?("quote")
    assert t.key?("position")
  end
end
