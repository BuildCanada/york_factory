class MediaClip < ApplicationRecord
  performs :export, queue_as: :default

  STATES = %w[queued processing ready failed].freeze
  EXPORT_MODES = %w[exact copy].freeze

  belongs_to :user
  belongs_to :media_recording,
    class_name: "Warehouse::MediaRecording",
    inverse_of: :media_clips
  belongs_to :recording,
    class_name: "Warehouse::MediaRecording",
    foreign_key: :media_recording_id,
    optional: true
  belongs_to :media_track,
    class_name: "Warehouse::MediaTrack",
    optional: true
  belongs_to :track,
    class_name: "Warehouse::MediaTrack",
    foreign_key: :media_track_id,
    optional: true

  has_one_attached :file
  has_many_attached :captions

  validates :title, presence: true, length: { maximum: 200 }
  validates :starts_at, :ends_at, presence: true
  validates :state, inclusion: { in: STATES }
  validates :export_mode, inclusion: { in: EXPORT_MODES }
  validate :valid_requested_range
  validate :requested_range_is_bounded
  validate :requested_range_is_within_recording
  validate :valid_actual_range
  validate :track_belongs_to_recording_stream
  validate :selected_track_is_audio

  scope :visible_to, ->(user) { where(user:) }

  def export
    Warehouse::Broadcasts::ClipExporter.new(self).call
  end

  # Kept in metadata so existing clips remain schema-compatible. Clips created
  # before export modes were introduced used stream copy.
  def export_mode
    metadata.to_h["export_mode"].presence || "copy"
  end

  def export_mode=(value)
    self.metadata = metadata.to_h.merge("export_mode" => value)
  end

  private

  def valid_requested_range
    return if starts_at.blank? || ends_at.blank? || ends_at > starts_at

    errors.add(:ends_at, "must be after starts at")
  end

  def valid_actual_range
    return if actual_starts_at.blank? || actual_ends_at.blank? || actual_ends_at > actual_starts_at

    errors.add(:actual_ends_at, "must be after actual starts at")
  end

  def requested_range_is_bounded
    return if starts_at.blank? || ends_at.blank? || ends_at - starts_at <= 30.minutes

    errors.add(:ends_at, "must be no more than 30 minutes after starts at")
  end

  def requested_range_is_within_recording
    return if starts_at.blank? || ends_at.blank? || media_recording.blank?

    errors.add(:starts_at, "must be within the recording") if starts_at < media_recording.starts_at
    if media_recording.ends_at.present? && ends_at > media_recording.ends_at
      errors.add(:ends_at, "must be within the recording")
    end
  end

  def track_belongs_to_recording_stream
    return if media_track.blank? || media_recording.blank?
    return if media_track.media_stream_id == media_recording.media_stream_id

    errors.add(:media_track, "must belong to the recording's media stream")
  end

  def selected_track_is_audio
    return if media_track.blank? || media_track.kind == "audio"

    errors.add(:media_track, "must be an audio track")
  end
end
