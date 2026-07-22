class HubspotEventsService
  def initialize
    @client = Hubspot::Client.new(access_token: Rails.application.credentials.dig(:hubspot, :access_token))
  end

  def upsert_event(luma_event, sync_guests: true)
    Rails.logger.info "Syncing Luma event #{luma_event.luma_event_id} to HubSpot"

    body = build_event_body(luma_event)
    external_event_id = "luma-#{luma_event.luma_event_id}"

    begin
      response = @client.marketing.events.basic_api.upsert(
        external_event_id: external_event_id,
        body: body
      )

      luma_event.update_column(:hubspot_synced_at, Time.current)
      Rails.logger.info "Successfully synced Luma event #{luma_event.luma_event_id} to HubSpot"


      raw_object_id = response.object_id

      # This might be {portalId}-{objectType}-{subType}-{objectId}
      # Marketing events are object type 0-54
      hubspot_event_id = "342054223-0-54-#{raw_object_id}" if raw_object_id

      # Create lists for the event
      create_event_lists(luma_event, hubspot_event_id)

      # Sync guests if requested and guests exist
      if sync_guests && luma_event.luma_event_guests.any?
        sync_event_guests(luma_event)
      end

    rescue StandardError => e
      Rails.logger.error "Error syncing event #{luma_event.luma_event_id} to HubSpot: #{e.message}"
      raise e
    end
  end

  # Sync all guests for a Luma event to HubSpot as attendees
  def sync_event_guests(luma_event)
    external_event_id = "luma-#{luma_event.luma_event_id}"

    Rails.logger.info "Syncing #{luma_event.luma_event_guests.count} guests for event #{luma_event.luma_event_id} to HubSpot"

    return if luma_event.luma_event_guests.empty?

    # Process guests in batches to avoid API limits
    luma_event.luma_event_guests.find_in_batches(batch_size: 100) do |guest_batch|
      sync_guest_batch(external_event_id, guest_batch)
    end

    Rails.logger.info "Completed syncing guests for event #{luma_event.luma_event_id}"
  end

  def create_event_lists(luma_event, hubspot_event_id = nil)
    return unless hubspot_event_id

    contact_statuses = [ "registered", "cancelled", "attended" ]

    contact_statuses.each do |status|
      list_name = generate_list_name(luma_event, status)

      begin
        create_hubspot_list(list_name, hubspot_event_id, status)
        Rails.logger.info "Created HubSpot list: #{list_name}"
      rescue => e
        Rails.logger.error "Failed to create HubSpot list '#{list_name}': #{e.message}"
      end
    end
  end

  private

  def generate_list_name(luma_event, contact_status)
    event_date = luma_event.start_at&.strftime("%Y-%m-%d") || Date.current.strftime("%Y-%m-%d")
    "#{luma_event.name} - #{event_date} - #{contact_status}"
  end

  def create_hubspot_list(list_name, hubspot_event_id, contact_status)
    filter_groups = build_list_filters(hubspot_event_id, contact_status)

    body = {
      name: list_name,
      objectTypeId: "0-1", # Contacts
      listFolderId: "508359647", # Events Folder
      processingType: "DYNAMIC",
      listType: "DYNAMIC",
      filterBranch: filter_groups      }


    Rails.logger.info "Creating HubSpot list: #{list_name}, #{body.to_json.inspect}"
    r = @client.api_request({
      method: "POST",
      path: "/crm/v3/lists",
      body: body }
    )

    if r.code == "200"
      Rails.logger.info "List #{list_name} created successfully"
    else
      Rails.logger.error "Failed to create list #{list_name}: #{r.body}"
      raise StandardError, r.body
    end
    r
  end

  def build_list_filters(hubspot_event_id, contact_status)
    event_type_id = case contact_status
    when "attended"
       "4-658938"  # Attended event type
    when "registered"
      "4-659238"  # Registered event type
    when "cancelled"
      "4-659239"  # Cancelled event type
    else
      raise ArgumentError, "Invalid contact status: #{contact_status}"
    end

    {
      "filterBranchOperator" => "OR",
      "filters" => [],
      "filterBranches" => [
        {
          "filterBranchOperator" => "AND",
          "filters" => [],
          "filterBranches" => [
            {
              "filterBranchOperator" => "AND",
              "filters" => [
                {
                  "filterType" => "PROPERTY",
                  "property" => "hs_marketing_event",
                  "operation" => {
                    "operationType" => "MULTISTRING",
                    "operator" => "IS_EQUAL_TO",
                    "defaultValue" => nil,
                    "includeObjectsWithNoValueSet" => false,
                    "values" => [ hubspot_event_id ],
                    "pruningRefineBy" => nil,
                    "coalescingRefineBy" => {
                      "setType" => "ANY",
                      "type" => "SetOccurrencesRefineBy"
                    },
                    "operatorName" => "IS_EQUAL_TO"
                  },
                  "frameworkFilterId" => nil,
                  "filterInsightsId" => 5,
                  "context" => nil
                }
              ],
              "filterBranches" => [],
              "filterInsightsId" => 4,
              "eventTypeId" => event_type_id,
              # "coalescingRefineBy" => {
              #   "setType" => "ANY",
              #   "type" => "SetOccurrencesRefineBy"
              # },
              "pruningRefineBy" => nil,
              "filterBranchType" => "UNIFIED_EVENTS",
              "operator" => "HAS_COMPLETED"
            }
          ],
          "filterInsightsId" => nil,
          "filterBranchType" => "AND"
        }
      ],
      "filterInsightsId" => nil,
      "filterBranchType" => "OR"
    }
  end

  def build_event_body(luma_event)
    {
      startDateTime: luma_event.start_at&.iso8601,
      endDateTime: luma_event.end_at&.iso8601,
      eventName: luma_event.name,
      eventDescription: build_enhanced_description(luma_event),
      eventUrl: luma_event.url,
      eventType: "Luma Event",
      eventCompleted: luma_event.past?,
      eventCancelled: false,
      eventOrganizer: "Build Canada",
      externalEventId: "luma-#{luma_event.luma_event_id}",
      externalAccountId: "luma",
      customProperties: build_custom_properties(luma_event)
    }.compact
  end

  def build_enhanced_description(luma_event)
    parts = []

    # Original description
    parts << luma_event.description if luma_event.description.present?

    # Add location info to description since we're not using custom properties for basic info
    location_parts = []
    location_parts << "📍 #{luma_event.location_name}" if luma_event.location_name.present?
    location_parts << "📍 #{luma_event.location_address}" if luma_event.location_address.present?

    if location_parts.any?
      parts << location_parts.join(" - ")
    end

    # Add other metadata
    metadata = []
    metadata << "🌍 #{luma_event.timezone}" if luma_event.timezone.present?
    metadata << "👁️ #{luma_event.visibility.capitalize}" if luma_event.visibility.present?
    metadata << "⏱️ #{luma_event.duration_hours}h" if luma_event.duration_hours.present?

    if metadata.any?
      parts << metadata.join(" • ")
    end

    parts.join("\n\n")
  end

  def build_custom_properties(luma_event)
    properties = []

    # Use existing HubSpot properties where possible, only add truly unique ones
    properties << build_property("location_name", luma_event.location_name) if luma_event.location_name.present?
    properties << build_property("location_address", luma_event.location_address) if luma_event.location_address.present?
    properties << build_property("timezone", luma_event.timezone) if luma_event.timezone.present?
    properties << build_property("visibility", luma_event.visibility) if luma_event.visibility.present?
    properties << build_property("approved_guests", luma_event.approved_guests.to_s) if luma_event.approved_guests > 0
    properties << build_property("duration_hours", luma_event.duration_hours.to_s) if luma_event.duration_hours.present?

    # Map to existing HubSpot properties via standard fields:
    # - luma_event_id -> externalEventId (already handled above)
    # - total_guests -> will be set via registrations update
    # - checked_in_guests -> will be set via attendees update

    properties
  end

  def build_property(name, value)
    {
      name: name,
      value: value,
      sourceId: "luma",
      source: "API",
      sourceLabel: "Luma Events",
      dataSensitivity: "none",
      timestamp: Time.current.to_i * 1000 # HubSpot expects milliseconds
    }
  end

  # Update HubSpot's built-in registration and attendance numbers
  def update_event_metrics(luma_event, hubspot_event_id)
    return unless hubspot_event_id.present?

    begin
      # Update registrations count using HubSpot's built-in field
      if luma_event.total_guests > 0
        @client.api_request({
          method: "PATCH",
          path: "/crm/v3/objects/marketing_event/#{hubspot_event_id}",
          body: {
            properties: {
              hs_registrations: luma_event.total_guests.to_s
            }
          }
        })
      end

      # Update attendees count using HubSpot's built-in field
      if luma_event.checked_in_guests > 0
        @client.api_request({
          method: "PATCH",
          path: "/crm/v3/objects/marketing_event/#{hubspot_event_id}",
          body: {
            properties: {
              hs_attendees: luma_event.checked_in_guests.to_s
            }
          }
        })
      end

      Rails.logger.info "Updated HubSpot event metrics for #{luma_event.luma_event_id}"
    rescue => e
      Rails.logger.error "Failed to update HubSpot event metrics: #{e.message}"
    end
  end

  private

  def sync_guest_batch(external_event_id, guests)
    # Separate guests by their state and approval status
    approved_guests = guests.select { |g| g.approval_status == "approved" }
    attended_guests = guests.select { |g| g.checked_in? }
    declined_guests = guests.select { |g| g.approval_status == "declined" }
    waitlist_guests = guests.select { |g| g.approval_status == "waitlist" }
    session_guests = guests.select { |g| g.approval_status == "session" }
    pending_guests = guests.select { |g| g.approval_status == "pending_approval" }
    invited_guests = guests.select { |g| g.approval_status == "invited" }

    # Sync approved guests as registered
    if approved_guests.any?
      sync_guests_with_state(external_event_id, approved_guests, "register")
    end

    # Sync attended guests (these override registration status)
    if attended_guests.any?
      sync_guests_with_state(external_event_id, attended_guests, "attend")
    end

    # Sync declined guests - these are leads who showed interest but declined
    if declined_guests.any?
      sync_guests_with_state(external_event_id, declined_guests, "cancel")
    end

    # Sync waitlist guests - these are potential leads waiting for approval
    if waitlist_guests.any?
      sync_guests_with_state(external_event_id, waitlist_guests, "register")
    end

    # Sync session guests - these are in active session/review
    if session_guests.any?
      sync_guests_with_state(external_event_id, session_guests, "register")
    end

    # Sync pending approval guests - waiting for organizer approval
    if pending_guests.any?
      sync_guests_with_state(external_event_id, pending_guests, "register")
    end

    # Sync invited guests - invited but haven't responded yet
    if invited_guests.any?
      sync_guests_with_state(external_event_id, invited_guests, "register")
    end
  end

  def sync_guests_with_state(external_event_id, guests, state)
    inputs = guests.map { |guest| build_guest_input(guest) }.compact

    return if inputs.empty?


    puts "Syncing #{inputs.size} #{state} guests to HubSpot"

    begin
      response = @client.api_request({
        method: "POST",
        path: "/marketing/v3/marketing-events/attendance/#{external_event_id}/#{state}/email-create?externalAccountId=luma",
        body: {
          inputs: inputs
        }
      })

      Rails.logger.info(response.body)
      if response && response.code.to_i >= 200 && response.code.to_i < 300
        Rails.logger.info "Successfully synced #{inputs.size} #{state} guests to HubSpot"
      else
        Rails.logger.error "Failed to sync #{state} guests: HTTP #{response.code} - #{response.body}"
      end

    rescue => e
      Rails.logger.error "Error syncing #{state} guests to HubSpot: #{e.message}"
    end
  end

  def build_guest_input(guest)
    return nil unless guest.email.present?

    {
      email: guest.email,
      externalAccountId: guest.luma_user_id,
      interactionDateTime: (guest.registered_at || guest.created_at).to_i * 1000, # HubSpot expects milliseconds
      contactProperties: build_guest_contact_properties(guest),
      properties: build_guest_event_properties(guest)
    }
  end

  def build_guest_contact_properties(guest)
    properties = {}

    # Basic contact info - split name into first/last if possible
    if guest.name.present?
      name_parts = guest.name.split(" ", 2)
      properties["firstname"] = name_parts.first
      properties["lastname"] = name_parts.last if name_parts.size > 1
    end

    properties
  end

  def build_guest_event_properties(guest)
    properties = {}

    # Event attendance details
    properties["approval_status"] = guest.approval_status if guest.approval_status.present?
    properties["checked_in"] = guest.checked_in.to_s if guest.checked_in.present?
    properties["registration_source"] = "Luma"

    properties
  end
end
