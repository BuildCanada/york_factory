class TradeBarriers::Agreement < ApplicationRecord
  extend FriendlyId
  friendly_id :title, use: :history

  STATUSES = {
    awaiting_sponsorship:  "awaiting_sponsorship",
    under_negotiation:     "under_negotiation",
    agreement_reached:     "agreement_reached",
    partially_implemented: "partially_implemented",
    implemented:           "implemented",
    deferred:              "deferred"
  }.freeze

  enum :status, STATUSES, prefix: :status

  belongs_to :theme, class_name: "TradeBarriers::Theme", optional: true

  has_many :agreement_jurisdictions,
    class_name: "TradeBarriers::AgreementJurisdiction",
    dependent: :destroy
  has_many :jurisdictions,
    through: :agreement_jurisdictions,
    source: :jurisdiction

  has_many :histories,
    -> { order(date_entered: :desc) },
    class_name: "TradeBarriers::AgreementHistory",
    dependent: :destroy

  validates :title, presence: true
  validates :slug, presence: true, uniqueness: true

  accepts_nested_attributes_for :agreement_jurisdictions, allow_destroy: true
  accepts_nested_attributes_for :histories, allow_destroy: true

  scope :recent, -> { order(updated_at: :desc) }
end
