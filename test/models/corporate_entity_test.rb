require "test_helper"

class CorporateEntityTest < ActiveSupport::TestCase
  test "validates presence of jurisdiction, registry_id, legal_name" do
    entity = CorporateEntity.new
    assert_not entity.valid?
    assert_includes entity.errors[:jurisdiction], "can't be blank"
    assert_includes entity.errors[:registry_id], "can't be blank"
    assert_includes entity.errors[:legal_name], "can't be blank"
  end

  test "validates uniqueness of registry_id within jurisdiction" do
    CorporateEntity.create!(jurisdiction: "federal", registry_id: "123456", legal_name: "Test Corp")

    duplicate = CorporateEntity.new(jurisdiction: "federal", registry_id: "123456", legal_name: "Another Corp")
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:registry_id], "has already been taken"
  end

  test "allows same registry_id in different jurisdictions" do
    CorporateEntity.create!(jurisdiction: "federal", registry_id: "123456", legal_name: "Federal Corp")
    bc_corp = CorporateEntity.new(jurisdiction: "bc", registry_id: "123456", legal_name: "BC Corp")
    assert bc_corp.valid?
  end

  test "scopes work correctly" do
    federal = CorporateEntity.create!(jurisdiction: "federal", registry_id: "F1", legal_name: "Fed Corp", status: "Active")
    CorporateEntity.create!(jurisdiction: "bc", registry_id: "B1", legal_name: "BC Corp", status: "Dissolved")

    assert_equal [federal], CorporateEntity.federal.to_a
    assert_equal [federal], CorporateEntity.active.to_a
    assert_equal 2, CorporateEntity.by_jurisdiction("federal").count + CorporateEntity.by_jurisdiction("bc").count
  end

  test "belongs_to government_entity optionally" do
    entity = CorporateEntity.create!(jurisdiction: "federal", registry_id: "X1", legal_name: "Test Corp")
    assert_nil entity.government_entity

    govt = GovernmentEntity.create!(canonical_name: "Some Dept")
    entity.update!(government_entity: govt)
    assert_equal govt, entity.reload.government_entity
  end

  test "has_many corporate_entity_aliases" do
    entity = CorporateEntity.create!(jurisdiction: "federal", registry_id: "A1", legal_name: "Alpha Corp")
    entity.corporate_entity_aliases.create!(alias_name: "Alpha Inc")
    entity.corporate_entity_aliases.create!(alias_name: "Alpha Ltd")

    assert_equal 2, entity.corporate_entity_aliases.count
  end

  test "has_many director_appointments and corporate_directors" do
    entity = CorporateEntity.create!(jurisdiction: "federal", registry_id: "D1", legal_name: "Dir Corp")
    director = CorporateDirector.create!(full_name: "Jane Smith", normalized_name: "jane smith")
    DirectorAppointment.create!(corporate_entity: entity, corporate_director: director, role: "Director")

    assert_equal 1, entity.director_appointments.count
    assert_equal [director], entity.corporate_directors.to_a
  end
end
