class BusinessEstablishment < ApplicationRecord
  belongs_to :corporate_entity, optional: true
  belongs_to :standardized_address, optional: true
  belongs_to :raw_ingestion, optional: true

  validates :business_name, presence: true
  validates :province, presence: true

  scope :by_province, ->(p) { where(province: p) }
  scope :by_naics, ->(code) { where(naics_code: code) }
  scope :with_business_number, -> { where.not(business_number: nil) }
end
