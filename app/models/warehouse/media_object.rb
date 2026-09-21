class Warehouse::MediaObject < Warehouse::Record
  KINDS = %w[source_segment init manifest playback_part caption_file].freeze
  IMMUTABLE_COLUMNS = %w[
    media_stream_id media_track_id kind identity_key object_key checksum byte_size content_type
    starts_at ends_at epoch sequence
  ].freeze

  belongs_to :media_stream,
    class_name: "Warehouse::MediaStream",
    inverse_of: :media_objects
  belongs_to :stream,
    class_name: "Warehouse::MediaStream",
    foreign_key: :media_stream_id,
    optional: true
  belongs_to :media_track,
    class_name: "Warehouse::MediaTrack",
    inverse_of: :media_objects,
    optional: true
  belongs_to :track,
    class_name: "Warehouse::MediaTrack",
    foreign_key: :media_track_id,
    optional: true

  validates :kind, inclusion: { in: KINDS }
  validates :identity_key, :object_key, :checksum, :content_type, presence: true
  validates :identity_key, uniqueness: { scope: :media_stream_id }
  validates :object_key, uniqueness: true
  validates :byte_size, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :epoch, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :valid_time_range
  validate :track_belongs_to_stream
  validate :uploaded_bytes_are_immutable, on: :update

  scope :overlapping, ->(window_start, window_end) {
    where("starts_at < ? AND ends_at > ?", window_end, window_start)
  }

  scope :current_playback, -> {
    where(kind: "playback_part").where("metadata ->> 'superseded_by_id' IS NULL")
  }

  private

  def valid_time_range
    return if starts_at.blank? || ends_at.blank? || ends_at > starts_at

    errors.add(:ends_at, "must be after starts at")
  end

  def track_belongs_to_stream
    return if media_track.blank? || media_track.media_stream_id == media_stream_id

    errors.add(:media_track, "must belong to the same media stream")
  end

  def uploaded_bytes_are_immutable
    changed = changes_to_save.keys & IMMUTABLE_COLUMNS
    errors.add(:base, "uploaded media object attributes are immutable") if changed.any?
  end
end
