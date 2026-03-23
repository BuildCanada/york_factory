class GovernmentEntity < ApplicationRecord
  has_many :government_entity_aliases, dependent: :destroy
  has_many :fiscal_authorities, dependent: :destroy
  has_many :fiscal_expenditures, dependent: :destroy
  has_many :standard_object_expenditures, dependent: :destroy
  has_many :lobbying_activities, dependent: :nullify
  has_many :corporate_entities, dependent: :nullify

  has_object :entity_resolver

  validates :canonical_name, presence: true, uniqueness: true
  validates :org_id_infobase, uniqueness: true, allow_nil: true
end
