class LumaGuestSyncJob < ApplicationJob
  queue_as :default

  def perform(luma_event, approval_status: nil)
    Rails.logger.info "Starting Luma guest sync for event: #{luma_event.name} (#{luma_event.luma_event_id})"

    begin
      service = LumaService.new
      synced_count = 0
      new_guests = 0
      updated_guests = 0
      checked_in_changes = 0

      # Fetch all guests for this event
      guests_data = service.fetch_all_guests(
        luma_event.luma_event_id,
        approval_status: approval_status
      )

      Rails.logger.info "Retrieved #{guests_data.length} guests from Luma API"

      guests_data.each do |guest_data|
        # Try multiple possible fields for user API ID
        user_api_id = guest_data["user_api_id"] ||
                     guest_data["api_id"] ||
                     guest_data.dig("guest", "user_api_id") ||
                     guest_data.dig("guest", "api_id") ||
                     guest_data.dig("user", "api_id") ||
                     guest_data.dig("user", "user_api_id")

        next if user_api_id.blank?

        # Find or create LumaEventGuest
        guest = LumaEventGuest.find_or_initialize_by(
          luma_event: luma_event,
          luma_user_id: user_api_id
        )

        is_new = guest.new_record?

        # Track previous check-in status
        was_checked_in = guest.checked_in?

        # Sync the guest data
        sync_result = guest.sync_from_luma_data(guest_data)

        # Skip if sync failed (missing required data)
        unless sync_result
          Rails.logger.debug "Skipped guest sync due to missing data"
          next
        end

        if is_new
          new_guests += 1
          Rails.logger.debug "Created new guest: #{guest.name} (#{guest.email})"
        elsif guest.saved_changes.any?
          updated_guests += 1
          Rails.logger.debug "Updated guest: #{guest.name} (#{guest.email})"

          # Track check-in status changes
          if guest.check_in_status_changed?
            checked_in_changes += 1
            if guest.checked_in? && !was_checked_in
              Rails.logger.info "Guest checked in: #{guest.name} for #{luma_event.name}"
            elsif !guest.checked_in? && was_checked_in
              Rails.logger.info "Guest check-in status reverted: #{guest.name} for #{luma_event.name}"
            end
          end
        end

        synced_count += 1

        # Rate limiting
        sleep(0.05) if synced_count % 20 == 0
      end

      Rails.logger.info "Luma guest sync completed for #{luma_event.name}!"
      Rails.logger.info "Total processed: #{synced_count}, New: #{new_guests}, Updated: #{updated_guests}, Check-in changes: #{checked_in_changes}"

    rescue => e
      Rails.logger.error "Error during Luma guest sync for event #{luma_event.luma_event_id}: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      raise e
    end
  end

  def self.sync_all_event_guests
    LumaEvent.find_each do |luma_event|
      LumaGuestSyncJob.perform_later(luma_event)

      # Add small delay between events to avoid rate limiting
      sleep(0.1)
    end
  end

  def self.sync_upcoming_event_guests
    # Sync guests for events in the next month
    LumaEvent.upcoming.where("start_at <= ?", 1.month.from_now).find_each do |luma_event|
      LumaGuestSyncJob.perform_later(luma_event)

      # Add small delay between events to avoid rate limiting
      sleep(0.1)
    end
  end

  def self.sync_recent_event_guests
    # Sync guests for events in the past week (to catch late check-ins)
    LumaEvent.where(start_at: 1.week.ago..Time.current).find_each do |luma_event|
      LumaGuestSyncJob.perform_later(luma_event)

      # Add small delay between events to avoid rate limiting
      sleep(0.1)
    end
  end
end
