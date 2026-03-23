class CorporateDirector < ApplicationRecord
  has_many :director_appointments, dependent: :destroy
  has_many :corporate_entities, through: :director_appointments

  validates :full_name, presence: true
  validates :normalized_name, presence: true

  before_validation :set_normalized_name

  scope :multi_board, -> {
    joins(:director_appointments)
      .group(:id)
      .having("COUNT(DISTINCT director_appointments.corporate_entity_id) >= 3")
  }

  private

  def set_normalized_name
    self.normalized_name = full_name&.downcase&.strip&.gsub(/\s+/, " ")
  end
end
