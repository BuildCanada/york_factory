class NotificationBatch < ApplicationRecord
  MODES = %w[instant digest].freeze
  STATES = %w[open closed delivering delivered dead].freeze

  belongs_to :saved_search
  has_many :saved_search_matches, dependent: :nullify
  has_many :notification_deliveries, dependent: :destroy

  validates :mode, inclusion: { in: MODES }
  validates :state, inclusion: { in: STATES }
  validates :payload, presence: true, unless: -> { state == "open" }

  scope :open, -> { where(state: "open") }

  def close!(at: Time.current)
    with_lock do
      raise ArgumentError, "batch is already immutable" unless state == "open"
      raise ArgumentError, "cannot close an empty notification batch" unless saved_search_matches.exists?

      self.payload = build_payload if payload.blank?
      update!(state: "closed", closed_at: at)
      notification_deliveries.create!(
        channel: "email",
        idempotency_key: "notification-batch-#{id}-email"
      )
    end
    self
  end

  def build_payload
    {
      version: 1,
      event: "saved_search.matches",
      batch_id: id,
      occurred_at: Time.current.iso8601(6),
      saved_search: {
        id: saved_search_id,
        name: saved_search.name,
        realm: saved_search.realm
      },
      matches: saved_search_matches.includes(:searchable).map do |match|
        searchable = match.searchable
        data = searchable.search_data.to_h.deep_symbolize_keys
        {
          searchable_id: match.searchable_index_id,
          searchable_type: match.searchable_type,
          searchable_revision: match.searchable_revision,
          realm: searchable.class.search_realm,
          record_type: searchable.class.search_record_type,
          title: data[:title],
          summary: data[:summary],
          url: data[:canonical_url],
          matched_at: match.matched_at.iso8601(6),
          evidence: match.match_evidence
        }.compact
      end
    }
  end
end
