require "test_helper"

class Api::V1::Geo::CrosswalkControllerTest < ActionDispatch::IntegrationTest
  setup do
    @fsa = GeoBoundary.create!(
      boundary_type: "fsa", geo_uid: "M5V", name_en: "M5V",
      province_code: "35", census_year: 2021, population: 1000
    )
    @fed1 = GeoBoundary.create!(
      boundary_type: "fed", geo_uid: "35024", name_en: "Toronto Centre",
      province_code: "35", census_year: 2021, population: 100000
    )
    @fed2 = GeoBoundary.create!(
      boundary_type: "fed", geo_uid: "35025", name_en: "Spadina-Fort York",
      province_code: "35", census_year: 2021, population: 120000
    )
    GeoCrosswalk.create!(
      source: @fsa, target: @fed1,
      source_type: "fsa", target_type: "fed",
      overlap_population: 720, weight_source_to_target: 0.72,
      weight_target_to_source: 0.0072, da_count: 20, census_year: 2021
    )
    GeoCrosswalk.create!(
      source: @fsa, target: @fed2,
      source_type: "fsa", target_type: "fed",
      overlap_population: 280, weight_source_to_target: 0.28,
      weight_target_to_source: 0.0023, da_count: 14, census_year: 2021
    )
  end

  test "show returns crosswalk data for a source boundary" do
    get api_v1_geo_crosswalk_url, params: { geo_uid: "M5V", source_type: "fsa" }
    assert_response :success

    body = JSON.parse(response.body)
    assert_equal "M5V", body["source"]["geo_uid"]
    assert_equal "fsa", body["source"]["boundary_type"]
    assert_equal 2, body["crosswalks"].length
  end

  test "show filters by target_type" do
    # Add a CSD crosswalk
    csd = GeoBoundary.create!(boundary_type: "csd", geo_uid: "3520005", name_en: "Toronto", census_year: 2021)
    GeoCrosswalk.create!(
      source: @fsa, target: csd,
      source_type: "fsa", target_type: "csd",
      overlap_population: 1000, weight_source_to_target: 1.0,
      da_count: 34, census_year: 2021
    )

    get api_v1_geo_crosswalk_url, params: { geo_uid: "M5V", source_type: "fsa", target_type: "fed" }
    assert_response :success

    body = JSON.parse(response.body)
    assert_equal 2, body["crosswalks"].length
    body["crosswalks"].each do |cw|
      assert_equal "fed", cw["target"]["boundary_type"]
    end
  end

  test "show filters by min_weight" do
    get api_v1_geo_crosswalk_url, params: { geo_uid: "M5V", source_type: "fsa", min_weight: 0.5 }
    assert_response :success

    body = JSON.parse(response.body)
    assert_equal 1, body["crosswalks"].length
    assert_equal "Toronto Centre", body["crosswalks"].first["target"]["name_en"]
  end

  test "show returns crosswalks ordered by weight descending" do
    get api_v1_geo_crosswalk_url, params: { geo_uid: "M5V", source_type: "fsa" }
    body = JSON.parse(response.body)

    weights = body["crosswalks"].map { |cw| cw["weight"].to_f }
    assert_equal weights, weights.sort.reverse
  end

  test "show returns 404 for unknown boundary" do
    get api_v1_geo_crosswalk_url, params: { geo_uid: "Z9Z", source_type: "fsa" }
    assert_response :not_found
  end
end
