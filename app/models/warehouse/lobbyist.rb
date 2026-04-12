class Warehouse::Lobbyist < Warehouse::Record
  has_many :lobbying_activities, dependent: :destroy

  validates :name, presence: true
end
