require "test_helper"

class Api::V1::Geo::WardLookupControllerTest < ActionDispatch::IntegrationTest
  # Toronto ward uids carry the city's CSD uid, so the number a client routes on
  # is the last segment.
  BEACHES_EAST_YORK = "3520005-19".freeze

  def ward(geo_uid:, name:, centre_lat:, centre_lon:, boundary_type: "ward", census_year: 2021)
    Warehouse::GeoBoundary.create!(
      boundary_type: boundary_type, geo_uid: geo_uid, name_en: name,
      province_code: "35", census_year: census_year,
      geometry: square(centre_lat: centre_lat, centre_lon: centre_lon, size: 0.05)
    )
  end

  def postal(code, city: "TORONTO", lat:, lon:)
    Warehouse::PostalCode.find_or_create_by!(postal_code: code) do |p|
      p.city = city
      p.province_code = "ON"
      p.latitude = lat
      p.longitude = lon
    end
  end

  setup do
    @lat, @lon = 43.686, -79.313
    @ward = ward(geo_uid: BEACHES_EAST_YORK, name: "Beaches-East York", centre_lat: @lat, centre_lon: @lon)
    postal("M4C 1S9", lat: @lat, lon: @lon)
  end

  def lookup(params)
    get api_v1_geo_ward_lookup_url, params: params
    JSON.parse(response.body)
  end

  test "resolves a postal code to the ward containing it" do
    body = lookup(postal_code: "M4C1S9")

    assert_response :success
    assert body["found"]
    assert_equal "resolved", body["reason"]
    assert_equal "M4C 1S9", body["postal_code"]
    assert_equal "TORONTO", body["city"]
    refute body["unverified"]

    assert_equal BEACHES_EAST_YORK, body["ward"]["geo_uid"]
    assert_equal "Beaches-East York", body["ward"]["name_en"]
    assert_equal "ward", body["ward"]["boundary_type"]
    assert_equal 2021, body["ward"]["census_year"]
  end

  # The frontend builds /wards/19 from this, so it has to be an integer and not
  # a padded string the client has to parse out of a uid.
  test "ward_number is the bare ward number as an integer" do
    body = lookup(postal_code: "M4C 1S9")

    assert_equal 19, body["ward"]["ward_number"]
  end

  test "accepts any spacing and casing" do
    [ "m4c1s9", "M4C 1S9", "m4c 1s9", "M4C-1S9" ].each do |input|
      body = lookup(postal_code: input)
      assert body["found"], "#{input.inspect} should resolve"
      assert_equal "M4C 1S9", body["postal_code"]
    end
  end

  test "a postal code that is not a postal code is malformed, not an error" do
    body = lookup(postal_code: "not a postal code")

    assert_response :success
    refute body["found"]
    assert_equal "malformed_postal_code", body["reason"]
    assert_nil body["ward"]
    assert body["unverified"], "we could not judge, so the client should ask them to check"
  end

  test "a postal code we do not hold is unknown" do
    body = lookup(postal_code: "M4C 9Z9")

    assert_response :success
    refute body["found"]
    assert_equal "unknown_postal_code", body["reason"]
    assert body["unverified"]
  end

  test "a postal code outside every ward is outside_boundary, not unknown" do
    postal("K1A 0A9", city: "OTTAWA", lat: 45.42, lon: -75.69)

    body = lookup(postal_code: "K1A 0A9")

    assert_response :success
    refute body["found"]
    assert_equal "outside_boundary", body["reason"]
    assert_equal "OTTAWA", body["city"]
    refute body["unverified"], "we judged them outside — that is an answer, not a failure"
  end

  # Distinguishing our missing data from the reader being outside the city is
  # the whole point of the reason strings.
  test "with no ward boundaries loaded at all the failure is ours" do
    Warehouse::GeoBoundary.by_type("ward").delete_all

    body = lookup(postal_code: "M4C 1S9")

    assert_response :success
    refute body["found"]
    assert_equal "boundary_data_unavailable", body["reason"]
    assert body["unverified"]
    assert_equal "no-store", response.headers["Cache-Control"]
  end

  # A ward with no geometry cannot answer, and must not be mistaken for one.
  test "a ward row with null geometry does not count as loaded data" do
    Warehouse::GeoBoundary.by_type("ward").delete_all
    Warehouse::GeoBoundary.create!(
      boundary_type: "ward", geo_uid: "3520005-01", name_en: "Etobicoke North",
      province_code: "35", census_year: 2021
    )

    body = lookup(postal_code: "M4C 1S9")

    assert_equal "boundary_data_unavailable", body["reason"]
  end

  test "boundary_type defaults to ward and school board wards are opt-in" do
    ward(geo_uid: "TDSB-16", name: "TDSB Ward 16", centre_lat: @lat, centre_lon: @lon,
      boundary_type: "school_board_ward")

    assert_equal BEACHES_EAST_YORK, lookup(postal_code: "M4C 1S9")["ward"]["geo_uid"]

    body = lookup(postal_code: "M4C 1S9", boundary_type: "school_board_ward")
    assert_equal "TDSB-16", body["ward"]["geo_uid"]
    assert_equal "school_board_ward", body["ward"]["boundary_type"]
  end

  # School board ward uids are named, not numbered.
  test "ward_number is null where the uid does not end in a number" do
    Warehouse::GeoBoundary.by_type("ward").delete_all
    ward(geo_uid: "VIAMONDE-Toronto Centre", name: "Viamonde – Toronto Centre",
      centre_lat: @lat, centre_lon: @lon, boundary_type: "school_board_ward")

    body = lookup(postal_code: "M4C 1S9", boundary_type: "school_board_ward")

    assert body["found"]
    assert_nil body["ward"]["ward_number"]
  end

  # Once a post-2026 ward model lands beside the current one, the newer vintage
  # is the one people vote in.
  test "the most recent census year wins when two ward models overlap" do
    ward(geo_uid: "3520005-19", name: "Beaches-East York (2026)", centre_lat: @lat, centre_lon: @lon,
      census_year: 2026)

    body = lookup(postal_code: "M4C 1S9")

    assert_equal 2026, body["ward"]["census_year"]
    assert_equal "Beaches-East York (2026)", body["ward"]["name_en"]
  end

  test "a missing postal_code is the one case that is a bad request" do
    get api_v1_geo_ward_lookup_url

    assert_response :bad_request
    assert_equal "postal_code is required", JSON.parse(response.body)["error"]
  end

  test "a blank postal_code is a bad request too" do
    get api_v1_geo_ward_lookup_url, params: { postal_code: "" }

    assert_response :bad_request
  end

  # by_type would raise ArgumentError on an undefined enum value, which would be
  # a 500 for what is a client mistake.
  test "an unknown boundary_type is rejected rather than raising" do
    get api_v1_geo_ward_lookup_url, params: { postal_code: "M4C 1S9", boundary_type: "med" }

    assert_response :bad_request
    assert_match "med", JSON.parse(response.body)["error"]
  end

  test "resolved answers are publicly cacheable" do
    lookup(postal_code: "M4C 1S9")

    assert_response :success
    assert_match(/public/, response.headers["Cache-Control"])
  end

  private

  def square(centre_lat:, centre_lon:, size:)
    half = size / 2.0
    ring = [
      [ centre_lon - half, centre_lat - half ], [ centre_lon + half, centre_lat - half ],
      [ centre_lon + half, centre_lat + half ], [ centre_lon - half, centre_lat + half ],
      [ centre_lon - half, centre_lat - half ]
    ].map { |lon, lat| "#{lon} #{lat}" }.join(", ")

    "SRID=4326;MULTIPOLYGON(((#{ring})))"
  end
end
