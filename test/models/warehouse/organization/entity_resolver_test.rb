require "test_helper"

class Warehouse::Organization::EntityResolverTest < ActiveSupport::TestCase
  setup do
    @org = Warehouse::Organization.create!(canonical_name: "Department of Finance", org_id_infobase: 47)
    @org.organization_aliases.create!(alias_name: "Department of Finance")
    @resolver = Warehouse::Organization.new.entity_resolver
  end

  test "exact match returns organization with confidence 1.0" do
    result = @resolver.resolve(name: "Department of Finance")

    assert_equal @org, result.organization
    assert_equal 1.0, result.lineage_entry.confidence
    assert_equal "exact_match", result.lineage_entry.transformation_type
  end

  test "case-insensitive match returns organization" do
    result = @resolver.resolve(name: "department of finance")

    assert_equal @org, result.organization
    assert_equal 0.99, result.lineage_entry.confidence.to_f
    assert_equal "case_insensitive", result.lineage_entry.transformation_type
  end

  test "encoding normalization handles curly apostrophes" do
    # Create an org with a straight apostrophe
    org = Warehouse::Organization.create!(canonical_name: "Queen's Privy Council")
    org.organization_aliases.create!(alias_name: "Queen's Privy Council")

    # Resolve with curly apostrophe (Unicode right single quote U+2019)
    result = @resolver.resolve(name: "Queen\u2019s Privy Council")

    assert_equal org, result.organization
    assert_equal "encoding_normalized", result.lineage_entry.transformation_type
    assert_equal 0.95, result.lineage_entry.confidence.to_f
  end

  test "encoding normalization creates alias for future exact matches" do
    org = Warehouse::Organization.create!(canonical_name: "King's Privy Council")
    org.organization_aliases.create!(alias_name: "King's Privy Council")

    @resolver.resolve(name: "King\u2019s Privy Council")

    # Now the curly version should be an alias
    assert Warehouse::OrganizationAlias.exists?(alias_name: "King\u2019s Privy Council")
  end

  test "resolve_by_infobase_id creates organization if not exists" do
    result = @resolver.resolve_by_infobase_id(org_id: 999, org_name: "New Department")

    assert_equal "New Department", result.organization.canonical_name
    assert_equal 999, result.organization.org_id_infobase
    assert_equal "deterministic", result.lineage_entry.transformation_type
    assert_equal 1.0, result.lineage_entry.confidence.to_f
  end

  test "resolve_by_infobase_id reuses existing organization" do
    result = @resolver.resolve_by_infobase_id(org_id: 47, org_name: "Department of Finance")

    assert_equal @org.id, result.organization.id
  end

  test "lineage entry records source and target values" do
    result = @resolver.resolve(name: "Department of Finance")

    entry = result.lineage_entry
    assert_equal "organization_name", entry.source_field
    assert_equal "Department of Finance", entry.source_value
    assert_equal "organization_id", entry.target_field
    assert_equal @org.id.to_s, entry.target_value
  end
end
