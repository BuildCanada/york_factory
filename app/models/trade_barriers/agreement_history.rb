class TradeBarriers::AgreementHistory < ApplicationRecord
  belongs_to :agreement, class_name: "TradeBarriers::Agreement"

  validates :status, :date_entered, presence: true
end
