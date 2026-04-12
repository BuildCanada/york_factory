class Warehouse::OrganizationAlias < Warehouse::Record
  belongs_to :organization

  validates :alias_name, presence: true
  validates :alias_name, uniqueness: { scope: :valid_from }
end
