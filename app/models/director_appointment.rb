class DirectorAppointment < ApplicationRecord
  belongs_to :corporate_entity
  belongs_to :corporate_director

  validates :corporate_director_id, uniqueness: { scope: :corporate_entity_id }

  scope :current, -> { where(ceased_date: nil) }
  scope :historical, -> { where.not(ceased_date: nil) }
end
