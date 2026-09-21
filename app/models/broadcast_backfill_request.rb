class BroadcastBackfillRequest < ApplicationRecord
  SCOPES = %w[date_range stream].freeze
  MODES = %w[discover_only discover_and_queue].freeze
  STATES = %w[queued running completed failed].freeze
  MAX_RANGE_DAYS = 366
  LEASE_TTL = 5.minutes

  belongs_to :requested_by, class_name: "User"
  has_many :items, class_name: "BroadcastBackfillItem", foreign_key: :request_id,
    inverse_of: :request, dependent: :destroy

  validates :scope, inclusion: { in: SCOPES }
  validates :mode, inclusion: { in: MODES }
  validates :state, inclusion: { in: STATES }
  validates :processed_dates, :discovered_count, :queued_count, :completed_count,
    :failed_count, :skipped_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :valid_date_range
  validate :lease_fields_are_paired

  def self.create_for_range!(starts_on:, ends_on:, mode:, requested_by:)
    create!(scope: "date_range", mode:, starts_on:, ends_on:, requested_by:)
  end

  def self.queue_stream!(stream:, requested_by:)
    unless stream.provider == "cpac" && stream.kind == "on_demand"
      raise ArgumentError, "historical capture currently requires an on-demand CPAC stream"
    end

    transaction do
      request = create!(scope: "stream", mode: "discover_and_queue", requested_by:,
        state: "running", started_at: Time.current, orchestration_complete: true)
      item = request.items.create!(media_stream: stream)
      item.enqueue!
      request.reload
    end
  end

  def enqueue!
    with_lock do
      raise ActiveRecord::RecordInvalid, self unless state.in?(%w[queued failed])
      raise ActiveRecord::RecordInvalid, self if lease_expires_at&.future?

      token = SecureRandom.uuid
      update!(state: "queued", error: nil, finished_at: nil, orchestration_complete: false,
        lease_token: token, lease_expires_at: Time.current + LEASE_TTL)
      Warehouse::Broadcasts::BackfillJob.perform_later(id, token)
    end
    self
  end

  def retry!
    transaction do
      raise ActiveRecord::RecordInvalid, self unless state == "failed"

      retry_listing = Array(metadata["listing_errors"]).any?
      items.failed.update_all(state: "discovered", error: nil, started_at: nil, finished_at: nil,
        updated_at: Time.current)
      token = SecureRandom.uuid
      update!(state: "queued", error: nil, finished_at: nil, orchestration_complete: false,
        lease_token: token, lease_expires_at: Time.current + LEASE_TTL,
        processed_dates: retry_listing ? 0 : processed_dates,
        metadata: (retry_listing ? metadata.except("listing_errors") : metadata).except("orchestration_failures"))
      refresh_progress!
      Warehouse::Broadcasts::BackfillJob.perform_later(id, token)
    end
    self
  end

  def refresh_progress!
    with_lock do
      counts = items.group(:state).count
      attributes = {
        discovered_count: items.count,
        queued_count: counts.fetch("queued", 0) + counts.fetch("running", 0),
        completed_count: counts.fetch("completed", 0),
        failed_count: counts.fetch("failed", 0),
        skipped_count: counts.fetch("skipped", 0)
      }
      terminal = orchestration_complete? &&
        counts.keys.all? { |item_state| item_state.in?(%w[completed failed skipped]) }
      has_listing_errors = Array(metadata["listing_errors"]).any?
      attributes.merge!(state: counts.fetch("failed", 0).positive? || has_listing_errors ? "failed" : "completed",
        finished_at: Time.current) if terminal
      update!(attributes)
    end
  end

  def renew_lease!(token)
    with_lock do
      return false unless lease_token.present? && ActiveSupport::SecurityUtils.secure_compare(lease_token, token.to_s)

      update!(lease_expires_at: Time.current + LEASE_TTL)
      true
    end
  end

  def release_lease!(token)
    with_lock do
      return false unless lease_token.present? && ActiveSupport::SecurityUtils.secure_compare(lease_token, token.to_s)

      update!(lease_token: nil, lease_expires_at: nil)
      true
    end
  end

  def fail_lease!(token, error)
    with_lock do
      return false unless lease_token.present? && ActiveSupport::SecurityUtils.secure_compare(lease_token, token.to_s)

      update!(state: "failed", error: "#{error.class}: #{error.message}".truncate(2_000),
        finished_at: Time.current, lease_token: nil, lease_expires_at: nil)
      true
    end
  end

  def record_lease_error!(token, error, max_attempts: 3)
    with_lock do
      return false unless lease_token.present? && ActiveSupport::SecurityUtils.secure_compare(lease_token, token.to_s)

      failures = metadata.fetch("orchestration_failures", 0).to_i + 1
      attributes = {
        error: "#{error.class}: #{error.message}".truncate(2_000),
        metadata: metadata.merge("orchestration_failures" => failures)
      }
      if failures >= max_attempts
        attributes.merge!(state: "failed", finished_at: Time.current, lease_token: nil, lease_expires_at: nil)
      end
      update!(attributes)
      failures < max_attempts
    end
  end

  def recover!
    with_lock do
      return false unless state.in?(%w[queued running])
      return false if lease_expires_at&.future?

      token = SecureRandom.uuid
      update!(lease_token: token, lease_expires_at: Time.current + LEASE_TTL)
      Warehouse::Broadcasts::BackfillJob.perform_later(id, token)
      true
    end
  end

  private

  def valid_date_range
    if scope == "date_range"
      errors.add(:starts_on, "is required") if starts_on.blank?
      errors.add(:ends_on, "is required") if ends_on.blank?
      return if starts_on.blank? || ends_on.blank?

      errors.add(:ends_on, "must be on or after the start date") if ends_on < starts_on
      errors.add(:ends_on, "cannot be more than #{MAX_RANGE_DAYS} days after the start date") if
        (ends_on - starts_on).to_i >= MAX_RANGE_DAYS
    elsif starts_on.present? || ends_on.present?
      errors.add(:starts_on, "must be blank for a stream request")
    end
  end

  def lease_fields_are_paired
    return if lease_token.present? == lease_expires_at.present?

    errors.add(:lease_token, "and lease expiry must both be present or absent")
  end
end
