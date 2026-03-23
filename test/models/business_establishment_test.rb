require "test_helper"

class BusinessEstablishmentTest < ActiveSupport::TestCase
  test "validates presence of business_name and province" do
    be = BusinessEstablishment.new
    assert_not be.valid?
    assert_includes be.errors[:business_name], "can't be blank"
    assert_includes be.errors[:province], "can't be blank"
  end

  test "creates establishment with all fields" do
    be = BusinessEstablishment.create!(
      business_name: "Acme Corp",
      trade_name: "Acme",
      business_number: "123456789RC0001",
      naics_code: "541510",
      naics_description: "Computer Systems Design",
      employee_size_range: "10-19",
      address: "123 Main St",
      city: "Toronto",
      province: "ON",
      postal_code: "M5V 1A1"
    )

    assert_equal "Acme Corp", be.business_name
    assert_equal "541510", be.naics_code
    assert_equal "ON", be.province
  end

  test "scopes filter correctly" do
    BusinessEstablishment.create!(business_name: "ON Biz", province: "ON", naics_code: "541510")
    BusinessEstablishment.create!(business_name: "BC Biz", province: "BC", naics_code: "722511")

    assert_equal 1, BusinessEstablishment.by_province("ON").count
    assert_equal 1, BusinessEstablishment.by_naics("541510").count
  end

  test "optional corporate_entity association" do
    be = BusinessEstablishment.create!(business_name: "Test Biz", province: "ON")
    assert_nil be.corporate_entity

    corp = CorporateEntity.create!(jurisdiction: "on", registry_id: "ON123", legal_name: "Test Corp")
    be.update!(corporate_entity: corp)
    assert_equal corp, be.reload.corporate_entity
  end
end
