class TradeBarriers::AgreementJurisdiction < ApplicationRecord
  STATUSES = {
    unknown:        "unknown",
    aware:          "aware",
    considering:    "considering",
    engaged:        "engaged",
    committed:      "committed",
    implementing:   "implementing",
    complete:       "complete",
    declined:       "declined",
    not_applicable: "not_applicable"
  }.freeze

  enum :status, STATUSES, prefix: :status

  belongs_to :agreement, class_name: "TradeBarriers::Agreement"
  belongs_to :jurisdiction, class_name: "Warehouse::Jurisdiction"

  has_many :histories,
    -> { order(date_entered: :desc) },
    class_name: "TradeBarriers::JurisdictionHistory",
    foreign_key: :agreement_jurisdiction_id,
    dependent: :destroy

  accepts_nested_attributes_for :histories, allow_destroy: true

  validates :agreement_id, uniqueness: { scope: :jurisdiction_id }
end
