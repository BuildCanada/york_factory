require "test_helper"

class Warehouse::Election::PledgeEligibilityTest < ActiveSupport::TestCase
  def jurisdiction(slug:, name:, code:)
    Warehouse::Jurisdiction.find_or_create_by!(slug: slug) do |j|
      j.name = name
      j.code = code
      j.level = "municipal"
      j.fiscal_year_start_month = 1
      j.default_currency = "CAD"
    end
  end

  def election_for(slug:, name:, code:, election_slug: nil)
    Warehouse::Election.find_or_create_by!(slug: election_slug || "#{slug}-2026") do |e|
      e.jurisdiction = jurisdiction(slug: slug, name: name, code: code)
      e.name = "#{name} 2026"
      e.kind = "municipal"
      e.election_date = Date.new(2026, 10, 26)
    end
  end

  def postal(code, city:, province: "ON", lat: 43.65, lon: -79.38)
    Warehouse::PostalCode.find_or_create_by!(postal_code: code) do |p|
      p.city = city
      p.province_code = province
      p.latitude = lat
      p.longitude = lon
    end
  end

  setup do
    @toronto = election_for(slug: "toronto", name: "City of Toronto", code: "TOR-ON")
    @hamilton = election_for(slug: "hamilton", name: "City of Hamilton", code: "HAM-ON")
  end

  test "an election in a jurisdiction with no rule is ungated" do
    election = election_for(slug: "sudbury", name: "City of Greater Sudbury", code: "SUD-ON")

    result = election.pledge_eligibility.check("P3A 1A1")

    assert result.eligible?
    assert_equal :no_rule, result.reason
    refute election.pledge_eligibility.gated?
  end

  test "a blank postal code is let through, as it always has been" do
    result = @toronto.pledge_eligibility.check("")

    assert result.eligible?
    assert_equal :no_postal_code, result.reason
  end

  test "a malformed postal code is rejected but flagged as unverified" do
    result = @toronto.pledge_eligibility.check("not a postal code")

    refute result.eligible?
    assert_equal :malformed_postal_code, result.reason
    assert result.indeterminate?
  end

  test "city name inside the region is eligible" do
    postal("L8P 1A1", city: "HAMILTON")

    result = @hamilton.pledge_eligibility.check("l8p1a1")

    assert result.eligible?
    assert_equal :city_match, result.reason
    assert_equal "L8P 1A1", result.postal_code
    assert_equal "HAMILTON", result.city
  end

  test "an amalgamated community counts as the city that absorbed it" do
    postal("L9H 1A1", city: "DUNDAS")
    postal("L0R 1A1", city: "BINBROOK")

    assert @hamilton.pledge_eligibility.check("L9H 1A1").eligible?, "Dundas is Hamilton"
    assert @hamilton.pledge_eligibility.check("L0R 1A1").eligible?, "Binbrook is Hamilton"
  end

  test "a neighbouring city is rejected" do
    postal("L9T 1A1", city: "MILTON")

    result = @hamilton.pledge_eligibility.check("L9T 1A1")

    refute result.eligible?
    assert_equal :city_mismatch, result.reason
    refute result.indeterminate?
  end

  # City names repeat across provinces: Dundas NB, Stoney Creek NB, Richmond BC.
  test "a same-named city in another province is rejected" do
    postal("E1G 1A1", city: "DUNDAS", province: "NB")

    result = @hamilton.pledge_eligibility.check("E1G 1A1")

    refute result.eligible?
    assert_equal :city_mismatch, result.reason
  end

  # Toronto owns every M FSA, so the prefix settles it and nothing else is
  # consulted — no postal row, no boundary.
  test "an M postal code is Toronto without any lookup at all" do
    @toronto.pledge_eligibility.rule # warm the jurisdiction load

    result = nil
    assert_queries_count(0) { result = @toronto.pledge_eligibility.check("m9c1a1") }

    assert result.eligible?
    assert_equal :fsa_match, result.reason
    assert_equal "M9C 1A1", result.postal_code
    assert_nil result.city, "nothing looked the city up on this path"
  end

  test "a non-Toronto FSA is still judged the long way" do
    # "York, ON" also exists in Haldimand, outside the city.
    postal("N0A 1A1", city: "YORK")

    result = @toronto.pledge_eligibility.check("N0A 1A1")

    refute result.eligible?
    assert_equal :city_mismatch, result.reason
  end

  # The two M FSAs Toronto does not own: M7R is a Mississauga large volume
  # receiver block, M0R is reserved.
  test "the M FSAs Toronto does not own skip the fast path" do
    postal("M7R 1A1", city: "MISSISSAUGA")
    postal("M0R 1A1", city: "MISSISSAUGA")

    %w[M7R\ 1A1 M0R\ 1A1].each do |code|
      result = @toronto.pledge_eligibility.check(code)

      refute result.eligible?, "#{code} is not Toronto"
      assert_equal :city_mismatch, result.reason
    end
  end

  test "an excluded M FSA we have never seen is not waved through as Toronto" do
    postal("L8P 1A1", city: "HAMILTON") # so ON postal data exists

    result = @toronto.pledge_eligibility.check("M7R 9Z9")

    refute result.eligible?
    assert_equal :unknown_postal_code, result.reason
  end

  test "an unknown postal code still counts where the city owns the whole FSA" do
    postal("L8P 1A1", city: "HAMILTON") # so ON postal data exists

    result = @toronto.pledge_eligibility.check("M5V 9Z9")

    assert result.eligible?
    assert_equal :fsa_match, result.reason
  end

  test "an unknown postal code is rejected where no FSA rule can judge it" do
    postal("L8P 1A1", city: "HAMILTON")

    result = @hamilton.pledge_eligibility.check("L9T 9Z9")

    refute result.eligible?
    assert_equal :unknown_postal_code, result.reason
    assert result.indeterminate?
  end

  # Rejecting every resident because an import never ran is worse than
  # accepting one who lives elsewhere.
  test "with no postal data loaded at all, pledges are allowed through" do
    assert_equal 0, Warehouse::PostalCode.in_province("ON").count

    result = @hamilton.pledge_eligibility.check("L8P 1A1")

    assert result.eligible?
    assert_equal :postal_data_unavailable, result.reason
  end

  # Hamilton's CSD, the one the rule names. Ontario has a second CSD called
  # "Hamilton" (a township in Northumberland), which is why rules key on UID.
  HAMILTON_CSD_UID = "3525005".freeze

  def hamilton_boundary
    Warehouse::GeoBoundary.create!(
      boundary_type: "csd", geo_uid: HAMILTON_CSD_UID, name_en: "Hamilton",
      province_code: "ON", census_year: 2021,
      geometry: square(centre_lat: 43.25, centre_lon: -79.87, size: 0.2)
    )
  end

  test "geometry admits a postal code the city list would have rejected" do
    hamilton_boundary
    # Canada Post labels plenty of addresses with a neighbour's city name.
    postal("L9T 1A1", city: "MILTON", lat: 43.25, lon: -79.87)

    result = @hamilton.pledge_eligibility.check("L9T 1A1")

    assert result.eligible?
    assert_equal :inside_boundary, result.reason
  end

  test "a point outside the boundary with an unrelated city name is rejected" do
    hamilton_boundary
    postal("L9T 1A1", city: "MILTON", lat: 45.42, lon: -75.69) # Ottawa's coordinates

    result = @hamilton.pledge_eligibility.check("L9T 1A1")

    refute result.eligible?
    assert_equal :outside_boundary, result.reason
  end

  # A postal code's centroid is the average of its delivery points, so near a
  # municipal line it can land on the wrong side of it. The city's own name for
  # the place rescues those rather than turning a resident away.
  test "a point just outside the boundary is rescued by the city name" do
    hamilton_boundary
    postal("L8P 1A1", city: "DUNDAS", lat: 45.42, lon: -75.69)

    result = @hamilton.pledge_eligibility.check("L8P 1A1")

    assert result.eligible?
    assert_equal :city_match, result.reason
  end

  test "the wrong Hamilton's boundary is not used" do
    # Hamilton Township, Northumberland — same name, different CSD.
    Warehouse::GeoBoundary.create!(
      boundary_type: "csd", geo_uid: "3514019", name_en: "Hamilton",
      province_code: "ON", census_year: 2021,
      geometry: square(centre_lat: 44.0, centre_lon: -78.2, size: 0.2)
    )
    postal("K9A 1A1", city: "COBOURG", lat: 44.0, lon: -78.2)

    result = @hamilton.pledge_eligibility.check("K9A 1A1")

    refute result.eligible?
    # Judged by name, because the city's own CSD is not loaded.
    assert_equal :city_mismatch, result.reason
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
