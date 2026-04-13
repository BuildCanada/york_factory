require "test_helper"

class AddressTest < ActiveSupport::TestCase
  setup do
    @address = Warehouse::Address.create!(
      oda_uid: "ODA-001",
      street_number: "123",
      street_name: "Main",
      street_type: "St",
      city: "Toronto",
      province_code: "35",
      postal_code: "M5V1A1",
      full_address: "123 Main St, Toronto ON M5V1A1",
      csd_uid: "3520005",
      csd_name: "Toronto",
      latitude: 43.6426,
      longitude: -79.3871
    )
  end

  test "validates presence of oda_uid" do
    address = Warehouse::Address.new(city: "Toronto")
    assert_not address.valid?
    assert address.errors[:oda_uid].any?
  end

  test "validates uniqueness of oda_uid" do
    duplicate = Warehouse::Address.new(oda_uid: "ODA-001", city: "Montreal")
    assert_not duplicate.valid?
    assert duplicate.errors[:oda_uid].any?
  end

  test "in_province scope filters correctly" do
    Warehouse::Address.create!(oda_uid: "ODA-002", province_code: "24", city: "Montreal")
    assert_equal 1, Warehouse::Address.in_province("35").count
    assert_equal 1, Warehouse::Address.in_province("24").count
  end

  test "in_postal_code scope filters correctly" do
    Warehouse::Address.create!(oda_uid: "ODA-002", postal_code: "H2X3Y7", city: "Montreal")
    assert_equal 1, Warehouse::Address.in_postal_code("M5V1A1").count
  end

  test "in_csd scope filters correctly" do
    Warehouse::Address.create!(oda_uid: "ODA-002", csd_uid: "2466023", city: "Montreal")
    assert_equal 1, Warehouse::Address.in_csd("3520005").count
  end

  test "search_street scope finds by partial name" do
    assert_equal 1, Warehouse::Address.search_street("Main").count
    assert_equal 0, Warehouse::Address.search_street("Oak").count
  end

  test "search_city scope finds by partial name" do
    assert_equal 1, Warehouse::Address.search_city("Toron").count
    assert_equal 0, Warehouse::Address.search_city("Vancouver").count
  end
end
