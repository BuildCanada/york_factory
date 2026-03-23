class CorporateRegistration < ApplicationRecord
  belongs_to :corporate_entity

  validates :event_type, presence: true

  scope :incorporations, -> { where(event_type: "incorporation") }
  scope :dissolutions, -> { where(event_type: "dissolution") }
  scope :amalgamations, -> { where(event_type: "amalgamation") }
end
