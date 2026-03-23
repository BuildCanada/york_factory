class StandardizedAddress < ApplicationRecord
  belongs_to :raw_ingestion, optional: true

  has_many :business_establishments, dependent: :nullify

  validates :full_address, presence: true
  validates :city, presence: true
  validates :province, presence: true
  validates :postal_code, presence: true
  validates :source_id, uniqueness: true, allow_nil: true

  scope :by_province, ->(p) { where(province: p) }
  scope :by_postal_code, ->(pc) { where(postal_code: pc) }
  scope :geocoded, -> { where.not(latitude: nil, longitude: nil) }
end
