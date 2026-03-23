class Lobbyist < ApplicationRecord
  has_many :lobbying_activities, dependent: :destroy

  validates :name, presence: true
end
