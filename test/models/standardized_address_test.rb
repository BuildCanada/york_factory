require "test_helper"

class StandardizedAddressTest < ActiveSupport::TestCase
  test "validates presence of required fields" do
    addr = StandardizedAddress.new
    assert_not addr.valid?
    assert_includes addr.errors[:full_address], "can't be blank"
    assert_includes addr.errors[:city], "can't be blank"
    assert_includes addr.errors[:province], "can't be blank"
    assert_includes addr.errors[:postal_code], "can't be blank"
  end

  test "creates address with all fields" do
    addr = StandardizedAddress.create!(
      full_address: "123 Main St, Toronto, ON M5V 1A1",
      street_name: "Main St",
      street_number: "123",
      city: "Toronto",
      province: "ON",
      postal_code: "M5V 1A1",
      latitude: 43.6532,
      longitude: -79.3832,
      source_id: "ODA-12345"
    )

    assert_equal "Toronto", addr.city
    assert_equal "ON", addr.province
    assert_in_delta 43.6532, addr.latitude.to_f, 0.001
  end

  test "source_id uniqueness" do
    StandardizedAddress.create!(
      full_address: "100 First Ave", city: "Ottawa", province: "ON",
      postal_code: "K1A 0A1", source_id: "UNIQUE-1"
    )

    duplicate = StandardizedAddress.new(
      full_address: "200 Second Ave", city: "Ottawa", province: "ON",
      postal_code: "K1A 0A2", source_id: "UNIQUE-1"
    )
    assert_not duplicate.valid?
  end

  test "scopes work correctly" do
    StandardizedAddress.create!(
      full_address: "1 Test", city: "Toronto", province: "ON",
      postal_code: "M5V 1A1", latitude: 43.0, longitude: -79.0
    )
    StandardizedAddress.create!(
      full_address: "2 Test", city: "Vancouver", province: "BC",
      postal_code: "V6B 1A1"
    )

    assert_equal 1, StandardizedAddress.by_province("ON").count
    assert_equal 1, StandardizedAddress.geocoded.count
  end
end
