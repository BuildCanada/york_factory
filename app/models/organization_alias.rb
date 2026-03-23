class OrganizationAlias < ApplicationRecord
  belongs_to :organization

  validates :alias_name, presence: true
  validates :alias_name, uniqueness: { scope: :valid_from }
end
