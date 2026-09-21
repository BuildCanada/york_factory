class Warehouse::MediaTranscriptPassage < Warehouse::Record
  STATES = %w[published withdrawn].freeze

  belongs_to :media_track,
    class_name: "Warehouse::MediaTrack",
    inverse_of: :media_transcript_passages
  belongs_to :track,
    class_name: "Warehouse::MediaTrack",
    foreign_key: :media_track_id,
    optional: true
  has_one :media_stream, through: :media_track
  has_one :stream, through: :track

  validates :window_key, presence: true, uniqueness: { scope: :media_track_id }
  validates :starts_at, :ends_at, presence: true
  validates :text, presence: true, if: :published?
  validates :state, inclusion: { in: STATES }
  validate :valid_time_range

  scope :published, -> { where(state: "published") }
  scope :overlapping, ->(window_start, window_end) {
    where("starts_at < ? AND ends_at > ?", window_end, window_start)
  }

  def published?
    state == "published"
  end

  # Existing saved-search matches use this stable identifier even though new
  # transcript searches are served directly from Postgres.
  def search_id
    raise ActiveRecord::RecordNotSaved, "transcript passage must be persisted" unless persisted?

    "media_transcript_passage:#{id}"
  end

  private

  def valid_time_range
    return if starts_at.blank? || ends_at.blank? || ends_at > starts_at

    errors.add(:ends_at, "must be after starts at")
  end
end
