class Warehouse::MediaTrack < Warehouse::Record
  KINDS = %w[video audio captions].freeze
  LANGUAGES = %w[en fr mul und].freeze
  DELIVERIES = %w[separate embedded].freeze

  belongs_to :media_stream,
    class_name: "Warehouse::MediaStream",
    inverse_of: :media_tracks
  belongs_to :stream,
    class_name: "Warehouse::MediaStream",
    foreign_key: :media_stream_id,
    optional: true
  belongs_to :parent_track,
    class_name: "Warehouse::MediaTrack",
    inverse_of: :child_tracks,
    optional: true

  has_many :child_tracks,
    class_name: "Warehouse::MediaTrack",
    foreign_key: :parent_track_id,
    inverse_of: :parent_track,
    dependent: :restrict_with_exception
  has_many :media_objects,
    class_name: "Warehouse::MediaObject",
    inverse_of: :media_track,
    dependent: :restrict_with_exception
  has_many :media_transcript_passages,
    class_name: "Warehouse::MediaTranscriptPassage",
    inverse_of: :media_track,
    dependent: :restrict_with_exception

  has_many :objects,
    class_name: "Warehouse::MediaObject",
    foreign_key: :media_track_id,
    inverse_of: :media_track
  has_many :passages,
    class_name: "Warehouse::MediaTranscriptPassage",
    foreign_key: :media_track_id,
    inverse_of: :media_track

  validates :track_key, :role, presence: true
  validates :track_key, uniqueness: { scope: :media_stream_id }
  validates :kind, inclusion: { in: KINDS }
  validates :language, inclusion: { in: LANGUAGES }
  validates :delivery, inclusion: { in: DELIVERIES }
  validates :first_seen_at, :last_seen_at, presence: true
  validate :parent_belongs_to_stream
  validate :parent_is_not_self
  validate :last_seen_not_before_first_seen

  private

  def parent_belongs_to_stream
    return if parent_track.blank? || parent_track.media_stream_id == media_stream_id

    errors.add(:parent_track, "must belong to the same media stream")
  end

  def parent_is_not_self
    errors.add(:parent_track, "cannot be itself") if persisted? && parent_track_id == id
  end

  def last_seen_not_before_first_seen
    return if first_seen_at.blank? || last_seen_at.blank? || last_seen_at >= first_seen_at

    errors.add(:last_seen_at, "must be on or after first seen at")
  end
end
