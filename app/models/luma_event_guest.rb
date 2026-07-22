class LumaEventGuest < ApplicationRecord
  belongs_to :luma_event

  validates :luma_user_id, presence: true, uniqueness: { scope: :luma_event_id }
  validates :name, presence: true
  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }

  scope :approved, -> { where(approval_status: "approved") }
  scope :pending, -> { where(approval_status: "pending_approval") }
  scope :checked_in, -> { where(checked_in: true) }
  scope :not_checked_in, -> { where(checked_in: false) }
  scope :needs_sync, -> { where("last_synced_at IS NULL OR last_synced_at < ?", 1.hour.ago) }

  def sync_from_luma_data(guest_data)
    # Handle nested guest structure from Luma API
    # The structure is: {"api_id": "...", "guest": {...}}
    actual_guest_data = guest_data["guest"] || guest_data

    # Extract name and email with fallbacks
    name = actual_guest_data["name"] ||
           actual_guest_data["user_name"] ||
           actual_guest_data["full_name"] ||
           "#{actual_guest_data["user_first_name"]} #{actual_guest_data["user_last_name"]}".strip ||
           "#{actual_guest_data["first_name"]} #{actual_guest_data["last_name"]}".strip

    email = actual_guest_data["email"] ||
            actual_guest_data["user_email"]

    # Skip if we don't have required data
    if name.blank? || email.blank?
      Rails.logger.warn "LumaEventGuest: Skipping guest sync - missing name (#{name.inspect}) or email (#{email.inspect})"
      Rails.logger.warn "Guest data: #{guest_data.inspect}"
      return false
    end

    # Determine if checked in
    checked_in = actual_guest_data["checked_in_at"].present? ||
                 actual_guest_data["check_in_time"].present? ||
                 guest_data["checked_in"] == true ||
                 guest_data["is_checked_in"] == true

    update!(
      name: name,
      email: email,
      approval_status: actual_guest_data["approval_status"] || actual_guest_data["status"] || "unknown",
      checked_in: checked_in,
      checked_in_at: parse_luma_datetime(actual_guest_data["checked_in_at"] || actual_guest_data["check_in_time"]),
      registered_at: parse_luma_datetime(actual_guest_data["registered_at"] || actual_guest_data["created_at"]),
      guest_data: guest_data, # Store the full response
      last_synced_at: Time.current
    )
  end

  def self.sync_guests_for_event(luma_event, inline: false)
    return LumaGuestSyncJob.perform_later(luma_event) unless inline

    service = LumaService.new
    service.fetch_all_guests(luma_event.luma_event_id).each do |guest_data|
      user_api_id = guest_data["user_api_id"] ||
                   guest_data["api_id"] ||
                   guest_data.dig("guest", "user_api_id") ||
                   guest_data.dig("guest", "api_id") ||
                   guest_data.dig("user", "api_id") ||
                   guest_data.dig("user", "user_api_id")

      next if user_api_id.blank?

      guest = find_or_initialize_by(
        luma_event: luma_event,
        luma_user_id: user_api_id
      )
      guest.sync_from_luma_data(guest_data)
    end
  end

  def check_in_status_changed?
    saved_change_to_checked_in? || saved_change_to_checked_in_at?
  end

  def recently_checked_in?
    checked_in? && checked_in_at.present? && checked_in_at > 1.hour.ago
  end

  private

  def parse_luma_datetime(datetime_string)
    return nil if datetime_string.blank?

    Time.parse(datetime_string)
  rescue ArgumentError
    nil
  end
end
