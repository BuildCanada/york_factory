class Warehouse::MediaStream < Warehouse::Record
  KINDS = %w[continuous event on_demand].freeze

  has_many :media_tracks,
    class_name: "Warehouse::MediaTrack",
    inverse_of: :media_stream,
    dependent: :restrict_with_exception
  has_many :media_objects,
    class_name: "Warehouse::MediaObject",
    inverse_of: :media_stream,
    dependent: :restrict_with_exception
  has_many :media_recordings,
    class_name: "Warehouse::MediaRecording",
    inverse_of: :media_stream,
    dependent: :restrict_with_exception
  has_many :media_transcript_passages, through: :media_tracks
  has_one :media_capture_state,
    class_name: "MediaCaptureState",
    inverse_of: :media_stream,
    dependent: :destroy
  has_many :broadcast_backfill_items,
    class_name: "BroadcastBackfillItem",
    foreign_key: :media_stream_id,
    dependent: :restrict_with_exception

  has_many :tracks,
    class_name: "Warehouse::MediaTrack",
    foreign_key: :media_stream_id,
    inverse_of: :media_stream
  has_many :objects,
    class_name: "Warehouse::MediaObject",
    foreign_key: :media_stream_id,
    inverse_of: :media_stream
  has_many :recordings,
    class_name: "Warehouse::MediaRecording",
    foreign_key: :media_stream_id,
    inverse_of: :media_stream
  has_many :passages, through: :tracks, source: :media_transcript_passages
  has_one :capture_state,
    class_name: "MediaCaptureState",
    foreign_key: :media_stream_id,
    inverse_of: :media_stream

  validates :provider, :external_id, presence: true
  validates :external_id, uniqueness: { scope: :provider }
  validates :kind, inclusion: { in: KINDS }
  validates :first_seen_at, :last_seen_at, presence: true
  validate :last_seen_not_before_first_seen

  private

  def last_seen_not_before_first_seen
    return if first_seen_at.blank? || last_seen_at.blank? || last_seen_at >= first_seen_at

    errors.add(:last_seen_at, "must be on or after first seen at")
  end
end
