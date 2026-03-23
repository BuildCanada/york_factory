class GovernmentEntityAlias < ApplicationRecord
  belongs_to :government_entity

  validates :alias_name, presence: true
  validates :alias_name, uniqueness: { scope: :valid_from }
end
