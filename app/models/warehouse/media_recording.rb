class Warehouse::MediaRecording < Warehouse::Record
  STATES = %w[open finalized partial].freeze

  belongs_to :media_stream,
    class_name: "Warehouse::MediaStream",
    inverse_of: :media_recordings
  belongs_to :stream,
    class_name: "Warehouse::MediaStream",
    foreign_key: :media_stream_id,
    optional: true
  has_many :media_clips,
    class_name: "MediaClip",
    inverse_of: :media_recording,
    dependent: :restrict_with_exception

  validates :recording_key, presence: true, uniqueness: { scope: :media_stream_id }
  validates :starts_at, presence: true
  validates :state, inclusion: { in: STATES }
  validate :valid_time_range

  scope :overlapping, ->(window_start, window_end) {
    where("starts_at < ? AND (ends_at IS NULL OR ends_at > ?)", window_end, window_start)
  }

  private

  def valid_time_range
    return if starts_at.blank? || ends_at.blank? || ends_at > starts_at

    errors.add(:ends_at, "must be after starts at")
  end
end
