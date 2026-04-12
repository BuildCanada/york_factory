class Lobbyist < WarehouseRecord
  has_many :lobbying_activities, dependent: :destroy

  validates :name, presence: true
end
