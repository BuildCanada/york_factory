class CorporateEntity < ApplicationRecord
  belongs_to :government_entity, optional: true
  belongs_to :raw_ingestion, optional: true

  has_many :corporate_entity_aliases, dependent: :destroy
  has_many :corporate_registrations, dependent: :destroy
  has_many :director_appointments, dependent: :destroy
  has_many :corporate_directors, through: :director_appointments
  has_many :business_establishments, dependent: :nullify

  has_object :enricher

  validates :jurisdiction, presence: true
  validates :registry_id, presence: true
  validates :legal_name, presence: true
  validates :registry_id, uniqueness: { scope: :jurisdiction }

  scope :federal, -> { where(jurisdiction: "federal") }
  scope :active, -> { where(status: "Active") }
  scope :needs_enrichment, -> { where(enriched: false) }
  scope :flagged, -> { where(needs_review: true) }
  scope :by_jurisdiction, ->(j) { where(jurisdiction: j) }
  scope :by_province, ->(p) { where(registered_office_province: p) }
end
