class CorporateEntityAlias < ApplicationRecord
  belongs_to :corporate_entity

  validates :alias_name, presence: true
  validates :alias_name, uniqueness: { scope: :corporate_entity_id }
end
