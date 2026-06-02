class ScopeOrganizationCanonicalNameUniqueness < ActiveRecord::Migration[8.1]
  def up
    remove_index "warehouse.organizations",
      name: "index_organizations_on_canonical_name",
      if_exists: true

    add_index "warehouse.organizations",
      [ :jurisdiction_id, :canonical_name ],
      unique: true,
      name: "idx_organizations_jurisdiction_canonical_name"
  end

  def down
    remove_index "warehouse.organizations",
      name: "idx_organizations_jurisdiction_canonical_name",
      if_exists: true

    add_index "warehouse.organizations",
      :canonical_name,
      unique: true,
      name: "index_organizations_on_canonical_name"
  end
end
