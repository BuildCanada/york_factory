class LumaEvent < ApplicationRecord
  performs :sync_to_hubspot

  has_many :luma_event_guests, dependent: :destroy

  validates :luma_event_id, presence: true, uniqueness: true
  validates :name, presence: true
  validates :start_at, presence: true

  scope :upcoming, -> { where("start_at > ?", Time.current) }
  scope :past, -> { where("start_at < ?", Time.current) }
  scope :by_visibility, ->(visibility) { where(visibility: visibility) }
  scope :needs_sync, -> { where("last_synced_at IS NULL OR last_synced_at < ?", 1.hour.ago) }
  scope :needs_hubspot_sync, -> { where("hubspot_synced_at IS NULL OR updated_at > hubspot_synced_at") }

  def sync_from_luma_data(luma_data)
    # Handle nested event structure from Luma API
    event_data = luma_data["event"] || luma_data

    was_new_record = new_record?

    update!(
      name: event_data["name"],
      description: event_data["description"] || event_data["description_md"],
      start_at: parse_luma_datetime(event_data["start_at"]),
      end_at: parse_luma_datetime(event_data["end_at"]),
      timezone: event_data["timezone"],
      visibility: event_data["visibility"],
      url: event_data["url"],
      location_name: extract_location_name(event_data),
      location_address: extract_location_address(event_data),
      created_at_luma: parse_luma_datetime(event_data["created_at"]),
      updated_at_luma: parse_luma_datetime(event_data["updated_at"]),
      event_data: luma_data, # Store the full response
      last_synced_at: Time.current
    )

    # Sync to HubSpot after updating
    sync_to_hubspot_if_needed
  end

  def self.sync_all_events(inline: false)
    return LumaEventSyncJob.perform_later unless inline

    LumaService.new.fetch_all_events.each do |event_data|
      api_id = event_data["api_id"] || event_data.dig("event", "api_id")
      next if api_id.blank?

      event = find_or_initialize_by(luma_event_id: api_id)
      event.sync_from_luma_data(event_data)
    end
  end

  def upcoming?
    start_at > Time.current
  end

  def past?
    start_at < Time.current
  end

  def duration_hours
    return nil unless end_at.present?

    ((end_at - start_at) / 1.hour).round(2)
  end

  def sync_guests(inline: false)
    LumaEventGuest.sync_guests_for_event(self, inline: inline)
  end

  def total_guests
    luma_event_guests.count
  end

  def checked_in_guests
    luma_event_guests.checked_in.count
  end

  def approved_guests
    luma_event_guests.approved.count
  end

  def sync_to_hubspot
    HubspotEventsService.new.upsert_event(self)
  end

  def sync_to_hubspot_if_needed
    return unless Rails.application.credentials.dig(:hubspot, :access_token).present?

    sync_to_hubspot_later
  end

  def self.sync_all_events_to_hubspot(inline: false)
    unless inline
      return needs_hubspot_sync.find_each { |event| event.sync_to_hubspot_later }
    end

    Rails.logger.info "Syncing #{needs_hubspot_sync.count} events to HubSpot"
    needs_hubspot_sync.find_each do |event|
      event.sync_to_hubspot
      sleep(0.1) # Rate limiting
    end
    Rails.logger.info "Finished syncing events to HubSpot"
  end

  private

  def parse_luma_datetime(datetime_string)
    return nil if datetime_string.blank?

    Time.parse(datetime_string)
  rescue ArgumentError
    nil
  end

  def extract_location_name(event_data)
    # Luma might not have a dedicated location name field
    # We can try to extract from geo data or use a default
    geo_json = event_data["geo_address_json"]
    return nil unless geo_json.present?

    # If geo_address_json is a string, parse it
    geo_data = geo_json.is_a?(String) ? JSON.parse(geo_json) : geo_json
    geo_data&.dig("name") || geo_data&.dig("venue_name")
  rescue JSON::ParserError
    nil
  end

  def extract_location_address(event_data)
    geo_json = event_data["geo_address_json"]
    return nil unless geo_json.present?

    # If geo_address_json is a string, parse it
    geo_data = geo_json.is_a?(String) ? JSON.parse(geo_json) : geo_json
    return nil unless geo_data

    parts = [
      geo_data["address"] || geo_data["street_address"],
      geo_data["city"],
      geo_data["region"] || geo_data["state"],
      geo_data["country"]
    ].compact.reject(&:blank?)

    parts.any? ? parts.join(", ") : nil
  rescue JSON::ParserError
    nil
  end
end
