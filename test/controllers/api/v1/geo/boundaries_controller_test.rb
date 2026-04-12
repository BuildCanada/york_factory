require "test_helper"

class Api::V1::Geo::BoundariesControllerTest < ActionDispatch::IntegrationTest
  setup do
    GeoBoundary.create!(boundary_type: "fsa", geo_uid: "M5V", name_en: "M5V", province_code: "35", census_year: 2021, population: 28000)
    GeoBoundary.create!(boundary_type: "fsa", geo_uid: "V6B", name_en: "V6B", province_code: "59", census_year: 2021, population: 15000)
    GeoBoundary.create!(boundary_type: "fed", geo_uid: "35024", name_en: "Toronto Centre", province_code: "35", census_year: 2021, population: 100000)
  end

  test "index returns all boundaries with pagination" do
    get api_v1_geo_boundaries_url
    assert_response :success

    body = JSON.parse(response.body)
    assert_equal 3, body["data"].length
    assert body.key?("pagination")
    assert_equal 3, body["pagination"]["count"]
  end

  test "index filters by boundary_type" do
    get api_v1_geo_boundaries_url, params: { boundary_type: "fsa" }
    assert_response :success

    body = JSON.parse(response.body)
    assert_equal 2, body["data"].length
    body["data"].each { |b| assert_equal "fsa", b["boundary_type"] }
  end

  test "index filters by province_code" do
    get api_v1_geo_boundaries_url, params: { province_code: "35" }
    assert_response :success

    body = JSON.parse(response.body)
    assert_equal 2, body["data"].length
  end

  test "index searches by name" do
    get api_v1_geo_boundaries_url, params: { q: "Toronto" }
    assert_response :success

    body = JSON.parse(response.body)
    assert_equal 1, body["data"].length
    assert_equal "Toronto Centre", body["data"].first["name_en"]
  end

  test "index returns empty results for no matches" do
    get api_v1_geo_boundaries_url, params: { q: "Nonexistent" }
    assert_response :success

    body = JSON.parse(response.body)
    assert_equal 0, body["data"].length
  end
end
