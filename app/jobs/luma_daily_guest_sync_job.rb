class LumaDailyGuestSyncJob < ApplicationJob
  queue_as :default

  def perform
    Rails.logger.info "Starting daily Luma guest sync"

    begin
      events_to_sync = 0

      # Find events that need daily syncing:
      # - Upcoming events (to catch new registrations)
      # - Events that happened up to 2 days ago (to catch late check-ins)
      cutoff_date = 2.days.ago

      events = LumaEvent.where(
        "start_at >= ? OR (start_at >= ? AND start_at <= ?)",
        cutoff_date,
        1.week.ago,
        Time.current
      )

      Rails.logger.info "Found #{events.count} events to sync guests for"

      events.find_each do |luma_event|
        Rails.logger.info "Syncing guests for event: #{luma_event.name} (#{luma_event.luma_event_id})"

        # Queue guest sync job for this event
        LumaGuestSyncJob.perform_later(luma_event)
        events_to_sync += 1

        # Add delay to avoid overwhelming the API
        sleep(0.1) if events_to_sync % 10 == 0
      end

      Rails.logger.info "Daily Luma guest sync completed!"
      Rails.logger.info "Queued guest sync for #{events_to_sync} events"

    rescue => e
      Rails.logger.error "Error during daily Luma guest sync: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      raise e
    end
  end
end
