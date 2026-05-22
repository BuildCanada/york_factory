class TradeBarriers::JurisdictionHistory < ApplicationRecord
  belongs_to :agreement_jurisdiction,
    class_name: "TradeBarriers::AgreementJurisdiction"

  validates :status, :date_entered, presence: true
end
