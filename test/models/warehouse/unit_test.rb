require "test_helper"

class Warehouse::UnitTest < ActiveSupport::TestCase
  test "absolute unit requires base_unit" do
    u = Warehouse::Unit.new(symbol: "test-abs-#{SecureRandom.hex(4)}", kind: "absolute")
    refute u.valid?
    assert u.errors[:base_unit].present?
  end

  test "qualitative unit must not have base_unit" do
    u = Warehouse::Unit.new(symbol: "test-q-#{SecureRandom.hex(4)}", kind: "qualitative", base_unit: "count")
    refute u.valid?
    assert u.errors[:base_unit].present?
  end

  test "rate unit requires denominator_unit" do
    u = Warehouse::Unit.new(symbol: "test-r-#{SecureRandom.hex(4)}", kind: "rate", base_unit: "dollars")
    refute u.valid?
    assert u.errors[:denominator_unit].present?
  end

  test "rate unit valid with denominator_unit" do
    u = Warehouse::Unit.new(symbol: "test-rok-#{SecureRandom.hex(4)}", kind: "rate", base_unit: "dollars",
                            denominator_unit: "square_meters", scale: 1.0)
    assert u.valid?
  end

  test "symbol is unique" do
    sym = "test-uniq-#{SecureRandom.hex(4)}"
    Warehouse::Unit.create!(symbol: sym, kind: "absolute", base_unit: "count")
    dup = Warehouse::Unit.new(symbol: sym, kind: "absolute", base_unit: "count")
    refute dup.valid?
  end
end
