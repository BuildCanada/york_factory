class LumaEventSyncJob < ApplicationJob
  queue_as :default

  def perform(start_date: nil, end_date: nil)
    Rails.logger.info "Starting Luma events sync"

    begin
      service = LumaService.new
      synced_count = 0
      new_events = 0
      updated_events = 0

      # Default date range: last 30 days to next 90 days
      start_date ||= 30.days.ago
      end_date ||= 90.days.from_now

      Rails.logger.info "Fetching Luma events from #{start_date} to #{end_date}"

      # Fetch all events in the date range
      events_data = service.fetch_all_events(
        after: start_date,
        before: end_date
      )

      Rails.logger.info "Retrieved #{events_data.length} events from Luma API"

      events_data.each do |event_data|
        api_id = event_data["api_id"] || event_data.dig("event", "api_id")
        next if api_id.blank?

        # Find or create LumaEvent
        luma_event = LumaEvent.find_or_initialize_by(luma_event_id: api_id)

        is_new = luma_event.new_record?

        # Sync the event data
        luma_event.sync_from_luma_data(event_data)

        if is_new
          new_events += 1
          Rails.logger.debug "Created new Luma event: #{luma_event.name} (#{luma_event.luma_event_id})"
        elsif luma_event.saved_changes.any?
          updated_events += 1
          Rails.logger.debug "Updated Luma event: #{luma_event.name} (#{luma_event.luma_event_id})"
        end

        synced_count += 1

        # Rate limiting
        sleep(0.1) if synced_count % 50 == 0
      end

      Rails.logger.info "Luma events sync completed!"
      Rails.logger.info "Total processed: #{synced_count}, New: #{new_events}, Updated: #{updated_events}"

    rescue => e
      Rails.logger.error "Error during Luma events sync: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      raise e
    end
  end

  def self.sync_upcoming_events
    # Sync events for the next 6 months
    LumaEventSyncJob.perform_later(
      start_date: Date.current,
      end_date: 6.months.from_now
    )
  end

  def self.sync_recent_events
    # Sync events from the last week to next month
    LumaEventSyncJob.perform_later(
      start_date: 1.week.ago,
      end_date: 1.month.from_now
    )
  end
end
