class TradeBarriers::Theme < ApplicationRecord
  has_many :agreements,
    class_name: "TradeBarriers::Agreement",
    foreign_key: :theme_id,
    dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: true

  scope :ordered, -> { order(:name) }
end
