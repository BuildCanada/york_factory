require "test_helper"

class Warehouse::OrganizationLineageTest < ActiveSupport::TestCase
  setup do
    @jurisdiction = Warehouse::Jurisdiction.find_or_create_by!(code: "TEST-OLT-#{SecureRandom.hex(2)}") do |j|
      j.name = "Test"
      j.slug = "test-olt-#{SecureRandom.hex(2)}"
      j.level = "municipal"
      j.fiscal_year_start_month = 1
      j.default_currency = "CAD"
    end
    @a = Warehouse::Organization.create!(jurisdiction: @jurisdiction, slug: "a-#{SecureRandom.hex(2)}", canonical_name: "A-#{SecureRandom.hex(2)}")
    @b = Warehouse::Organization.create!(jurisdiction: @jurisdiction, slug: "b-#{SecureRandom.hex(2)}", canonical_name: "B-#{SecureRandom.hex(2)}")
    @c = Warehouse::Organization.create!(jurisdiction: @jurisdiction, slug: "c-#{SecureRandom.hex(2)}", canonical_name: "C-#{SecureRandom.hex(2)}")
  end

  test "predecessor and successor must differ" do
    l = Warehouse::OrganizationLineage.new(predecessor: @a, successor: @a, transition_year: 2024, transition_kind: "rename")
    refute l.valid?
  end

  test "M-to-1 merge: two predecessors → same successor in same year" do
    Warehouse::OrganizationLineage.create!(predecessor: @a, successor: @c, transition_year: 2024, transition_kind: "merge")
    second = Warehouse::OrganizationLineage.new(predecessor: @b, successor: @c, transition_year: 2024, transition_kind: "merge")
    assert second.valid?, second.errors.full_messages.inspect
  end

  test "duplicate (pred, succ, year, kind) is rejected" do
    Warehouse::OrganizationLineage.create!(predecessor: @a, successor: @b, transition_year: 2024, transition_kind: "rename")
    dup = Warehouse::OrganizationLineage.new(predecessor: @a, successor: @b, transition_year: 2024, transition_kind: "rename")
    refute dup.valid?
  end

  test "same (pred, succ) with different transition_kind is allowed" do
    Warehouse::OrganizationLineage.create!(predecessor: @a, successor: @b, transition_year: 2024, transition_kind: "rename")
    other = Warehouse::OrganizationLineage.new(predecessor: @a, successor: @b, transition_year: 2024, transition_kind: "absorb")
    assert other.valid?
  end
end
