class SavedSearchMatch < ApplicationRecord
  STATES = %w[pending buffered dispatching delivered dead].freeze

  belongs_to :saved_search
  belongs_to :searchable, polymorphic: true
  belongs_to :notification_batch, optional: true

  before_validation :populate_searchable_snapshot, on: :create
  before_validation :populate_match_key, on: :create

  validates :searchable_revision,
    numericality: { only_integer: true, greater_than: 0 }
  validates :searchable_content_hash, :match_key, :matched_at, presence: true
  validates :state, inclusion: { in: STATES }
  validates :match_key, uniqueness: { scope: :saved_search_id }
  validate :notification_batch_accepts_match

  def searchable_index_id
    searchable.search_id
  end

  private

  def populate_searchable_snapshot
    return unless searchable

    self.searchable_revision ||= searchable.search_revision
    self.searchable_content_hash ||= searchable.search_content_hash
    self.matched_at ||= Time.current
    self.matched_sequence ||= searchable.search_index_sequence
  end

  def populate_match_key
    return if match_key.present? || !searchable

    self.match_key = if saved_search&.notify_on_update?
      "#{searchable_index_id}:#{searchable_content_hash}"
    else
      searchable_index_id
    end
  end

  def notification_batch_accepts_match
    return unless will_save_change_to_notification_batch_id?

    previous_batch = NotificationBatch.find_by(id: notification_batch_id_in_database)
    if previous_batch && previous_batch.state != "open"
      errors.add(:notification_batch, "cannot be changed after it closes")
      return
    end
    return unless notification_batch

    if notification_batch.saved_search_id != saved_search_id
      errors.add(:notification_batch, "must belong to the same saved search")
    end
    if notification_batch.state != "open"
      errors.add(:notification_batch, "must be open")
    end
  end
end
