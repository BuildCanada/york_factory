class MediaCaptureState < ApplicationRecord
  RELEASE_ATTRIBUTES = %i[
    enabled next_poll_at cursor consecutive_failures last_error last_captured_at last_processed_at
  ].freeze

  belongs_to :media_stream,
    class_name: "Warehouse::MediaStream",
    inverse_of: :media_capture_state
  belongs_to :stream,
    class_name: "Warehouse::MediaStream",
    foreign_key: :media_stream_id,
    optional: true

  validates :media_stream_id, uniqueness: true
  validates :consecutive_failures,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :lease_fields_are_paired

  scope :due, ->(at = Time.current) {
    where(enabled: true).where("next_poll_at IS NULL OR next_poll_at <= ?", at)
  }

  def claim!(now:, ttl:)
    validate_positive_ttl!(ttl)
      with_lock do
        return if !enabled? || (lease_token.present? && lease_expires_at > now)
        return if next_poll_at && next_poll_at > now

      token = SecureRandom.uuid
      update!(lease_token: token, lease_expires_at: now + ttl)
      token
    end
  end

  def renew_lease!(token:, now:, ttl:)
    validate_positive_ttl!(ttl)
    with_lock do
      return false unless lease_owned_without_lock?(token, now)

      update!(lease_expires_at: now + ttl)
      true
    end
  end

  def release_lease!(token:, now:, attrs: {})
    with_lock do
      return false unless lease_token.present? && ActiveSupport::SecurityUtils.secure_compare(lease_token, token.to_s)

      assign_fenced_attributes!(attrs)
      self.lease_token = nil
      self.lease_expires_at = nil
      save!
      true
    end
  end

  def update_cursor!(token:, now:, cursor:, attrs: {})
    with_lock do
      return false unless lease_owned_without_lock?(token, now)

      assign_fenced_attributes!(attrs.merge(cursor:))
      save!
      true
    end
  end

  def lease_owned?(token, now: Time.current)
    reload
    lease_owned_without_lock?(token, now)
  end

  private

  def lease_owned_without_lock?(token, now)
    lease_token.present? && lease_expires_at.present? && lease_expires_at > now &&
      ActiveSupport::SecurityUtils.secure_compare(lease_token, token.to_s)
  end

  def assign_fenced_attributes!(attrs)
    attributes = attrs.to_h.symbolize_keys
    unknown = attributes.keys - RELEASE_ATTRIBUTES
    raise ArgumentError, "unsupported capture state attributes: #{unknown.join(', ')}" if unknown.any?

    assign_attributes(attributes)
  end

  def validate_positive_ttl!(ttl)
    raise ArgumentError, "ttl must be positive" unless ttl.present? && ttl > 0
  end

  def lease_fields_are_paired
    return if lease_token.present? == lease_expires_at.present?

    errors.add(:lease_token, "and lease expiry must both be present or absent")
  end
end
