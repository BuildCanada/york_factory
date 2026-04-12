require "test_helper"

class Api::V1::Geo::AddressesControllerTest < ActionDispatch::IntegrationTest
  setup do
    Address.create!(oda_uid: "ODA-001", street_number: "123", street_name: "Main", street_type: "St",
                    city: "Toronto", province_code: "35", postal_code: "M5V1A1",
                    full_address: "123 Main St, Toronto ON M5V1A1", csd_uid: "3520005", csd_name: "Toronto",
                    latitude: 43.6426, longitude: -79.3871)
    Address.create!(oda_uid: "ODA-002", street_number: "456", street_name: "Granville", street_type: "St",
                    city: "Vancouver", province_code: "59", postal_code: "V6B2J2",
                    full_address: "456 Granville St, Vancouver BC V6B2J2", csd_uid: "5915022", csd_name: "Vancouver",
                    latitude: 49.2827, longitude: -123.1207)
    Address.create!(oda_uid: "ODA-003", street_number: "789", street_name: "King", street_type: "St",
                    city: "Toronto", province_code: "35", postal_code: "M5V1A1",
                    full_address: "789 King St, Toronto ON M5V1A1", csd_uid: "3520005", csd_name: "Toronto",
                    latitude: 43.6450, longitude: -79.3900)
  end

  test "index returns all addresses with pagination" do
    get api_v1_geo_addresses_url
    assert_response :success

    body = JSON.parse(response.body)
    assert_equal 3, body["data"].length
    assert body.key?("pagination")
    assert_equal 3, body["pagination"]["count"]
  end

  test "index filters by province_code" do
    get api_v1_geo_addresses_url, params: { province_code: "35" }
    assert_response :success

    body = JSON.parse(response.body)
    assert_equal 2, body["data"].length
    body["data"].each { |a| assert_equal "35", a["province_code"] }
  end

  test "index filters by postal_code" do
    get api_v1_geo_addresses_url, params: { postal_code: "M5V1A1" }
    assert_response :success

    body = JSON.parse(response.body)
    assert_equal 2, body["data"].length
  end

  test "index filters by csd_uid" do
    get api_v1_geo_addresses_url, params: { csd_uid: "5915022" }
    assert_response :success

    body = JSON.parse(response.body)
    assert_equal 1, body["data"].length
    assert_equal "Vancouver", body["data"].first["city"]
  end

  test "index searches by street name" do
    get api_v1_geo_addresses_url, params: { street: "Main" }
    assert_response :success

    body = JSON.parse(response.body)
    assert_equal 1, body["data"].length
    assert_equal "Main", body["data"].first["street_name"]
  end

  test "index searches by city" do
    get api_v1_geo_addresses_url, params: { city: "Toronto" }
    assert_response :success

    body = JSON.parse(response.body)
    assert_equal 2, body["data"].length
  end

  test "index returns serialized address fields" do
    get api_v1_geo_addresses_url, params: { province_code: "59" }
    assert_response :success

    body = JSON.parse(response.body)
    address = body["data"].first
    assert_equal "ODA-002", address["oda_uid"]
    assert_equal "456 Granville St, Vancouver BC V6B2J2", address["full_address"]
    assert_equal "456", address["street_number"]
    assert_equal "Granville", address["street_name"]
    assert_equal "St", address["street_type"]
    assert_equal "Vancouver", address["city"]
    assert_equal "59", address["province_code"]
    assert_equal "V6B2J2", address["postal_code"]
    assert_equal "5915022", address["csd_uid"]
    assert_equal "Vancouver", address["csd_name"]
    assert_in_delta 49.2827, address["latitude"].to_f, 0.001
    assert_in_delta(-123.1207, address["longitude"].to_f, 0.001)
  end
end
