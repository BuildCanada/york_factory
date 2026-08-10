require "time"
require "hubspot/codegen/crm/contacts/api_error"

class HubspotSyncService
  MAX_ATTEMPTS = 5
  RETRYABLE_STATUSES = [ 408, 429 ].freeze

  class TransientError < StandardError
    attr_reader :retry_after

    def initialize(message, retry_after: nil)
      @retry_after = retry_after
      super(message)
    end
  end

  def self.sync_contact_to_hubspot(hubspot_contact)
    new.sync_contact_to_hubspot(hubspot_contact)
  end

  def self.fetch_contact_from_hubspot(hubspot_contact_id)
    new.fetch_contact_from_hubspot(hubspot_contact_id)
  end

  def self.test_api_connection(limit: 5)
    new.test_connection(limit: limit)
  end

  def initialize
    @client = Hubspot::Client.new(access_token: Rails.application.credentials.dig(:hubspot, :access_token))
  end

  def sync_contact_to_hubspot(hubspot_contact)
    Rails.logger.info "Syncing contact #{hubspot_contact.email} to Hubspot"

    properties = build_hubspot_properties(hubspot_contact)

    begin
      if hubspot_contact.hubspot_contact_id.present?
        # Update existing contact
        @client.crm.contacts.basic_api.update(
          contact_id: hubspot_contact.hubspot_contact_id,
          simple_public_object_input: { properties: properties }
        )
        Rails.logger.info "Updated Hubspot contact: #{hubspot_contact.email}"
      else
        # Create new contact
        response = @client.crm.contacts.basic_api.create(
          simple_public_object_input_for_create: { properties: properties }
        )

        # Update our local record with the Hubspot ID
        hubspot_contact.update!(hubspot_contact_id: response.id)
        Rails.logger.info "Created new Hubspot contact: #{hubspot_contact.email} with ID: #{response.id}"
      end

      hubspot_contact.update!(synced_at: Time.current)

    rescue Hubspot::Crm::Contacts::ApiError => error
      if retryable?(error)
        Rails.logger.warn "Retryable Hubspot API error for contact #{hubspot_contact.email}: #{error.message}"
        raise transient_error(error)
      end

      Rails.logger.error "Hubspot API error for contact #{hubspot_contact.email}: #{error.message}"
      raise
    rescue StandardError => error
      Rails.logger.error "Error syncing contact #{hubspot_contact.email} to Hubspot: #{error.message}"
      raise
    end
  end

  def fetch_contact_from_hubspot(hubspot_contact_id)
    # Use the properties defined in the model constant
    properties = HubspotContact.hubspot_property_names

    begin
      response = @client.crm.contacts.basic_api.get_by_id(
        contact_id: hubspot_contact_id,
        properties: properties
      )

      HubspotContact.from_hubspot_properties(response.properties)
    rescue StandardError => e
      Rails.logger.error "Hubspot API error fetching contact #{hubspot_contact_id}: #{e.message}"
      raise e
    end
  end

  def sync_all_contacts_from_hubspot
    Rails.logger.info "Starting bulk sync of all contacts from Hubspot"

    properties = HubspotContact.hubspot_property_names
    limit = 100
    after = nil
    total_synced = 0
    total_processed = 0
    batch_count = 0

    begin
      loop do
        batch_count += 1
        Rails.logger.info "Fetching batch #{batch_count} of contacts (after: #{after})"

        response = @client.crm.contacts.basic_api.get_page(
          limit: limit,
          after: after,
          properties: properties,
          archived: false
        )

        contacts = response.results
        break if contacts.empty?

        Rails.logger.info "Processing #{contacts.size} contacts in batch #{batch_count}"

        contacts.each do |hubspot_contact_data|
          total_processed += 1
          begin
            contact = HubspotContact.from_hubspot_properties(hubspot_contact_data.properties)
            contact.skip_hubspot_sync!

            if contact.save
              total_synced += 1
              Rails.logger.debug "Synced contact: #{contact.email}"
            else
              Rails.logger.warn "Failed to save contact: #{contact.errors.full_messages.join(', ')}"
            end
          rescue => e
            Rails.logger.error "Error processing contact #{hubspot_contact_data.id}: #{e.message}"
          end
        end

        # Check for pagination
        after = response.paging&._next&.after
        break unless after

        # Progress logging
        Rails.logger.info "Batch #{batch_count} completed. Total processed: #{total_processed}, Total synced: #{total_synced}"

        # Rate limiting - small delay between batches
        sleep(0.1)
      end

      Rails.logger.info "Bulk sync completed. Processed: #{total_processed}, Successfully synced: #{total_synced}"
    rescue StandardError => e
      Rails.logger.error "Hubspot API error during bulk sync: #{e.message}"
      Rails.logger.error "Processed #{total_processed} contacts before error, synced #{total_synced}"
      raise e
    rescue => e
      Rails.logger.error "Unexpected error during bulk sync: #{e.message}"
      Rails.logger.error "Processed #{total_processed} contacts before error, synced #{total_synced}"
      raise e
    end
  end

  def sync_stale_contacts_from_hubspot
    Rails.logger.info "Syncing stale contacts from Hubspot"

    # Get contacts that haven't been synced in the last hour or never synced
    stale_contacts = HubspotContact.stale

    stale_contacts.find_each do |contact|
      begin
        updated_contact = fetch_contact_from_hubspot(contact.hubspot_contact_id)
        updated_contact.skip_hubspot_sync!
        updated_contact.save!
        Rails.logger.debug "Refreshed stale contact: #{contact.email}"
      rescue => e
        Rails.logger.error "Error refreshing stale contact #{contact.hubspot_contact_id}: #{e.message}"
      end
    end

    Rails.logger.info "Completed syncing #{stale_contacts.count} stale contacts"
  end

  def sync_recently_updated_contacts_from_hubspot(hours: 24)
    Rails.logger.info "Syncing recently updated contacts from Hubspot (last #{hours} hours)"

    properties = HubspotContact.hubspot_property_names
    limit = 100
    after = nil
    total_synced = 0

    # Calculate timestamp for filtering (Hubspot uses milliseconds)
    since_timestamp = (hours.hours.ago.to_f * 1000).to_i

    begin
      loop do
        response = @client.crm.contacts.basic_api.get_page(
          limit: limit,
          after: after,
          properties: properties,
          archived: false
        )

        contacts = response.results
        break if contacts.empty?

        contacts.each do |hubspot_contact_data|
          # Check if contact was updated recently
          updated_at = hubspot_contact_data.properties["lastmodifieddate"]
          next unless updated_at && updated_at.to_i >= since_timestamp

          begin
            contact = HubspotContact.from_hubspot_properties(hubspot_contact_data.properties)
            contact.skip_hubspot_sync!

            if contact.save
              total_synced += 1
              Rails.logger.debug "Synced recently updated contact: #{contact.email}"
            else
              Rails.logger.warn "Failed to save contact: #{contact.errors.full_messages.join(', ')}"
            end
          rescue => e
            Rails.logger.error "Error processing contact #{hubspot_contact_data.id}: #{e.message}"
          end
        end

        after = response.paging&._next&.after
        break unless after

        sleep(0.1)
      end

      Rails.logger.info "Recently updated contacts sync completed. Total contacts synced: #{total_synced}"
    rescue StandardError => e
      Rails.logger.error "Hubspot API error during recent contacts sync: #{e.message}"
      raise e
    end
  end

  private

  def retryable?(error)
    status = Integer(error.code, exception: false)
    status && (RETRYABLE_STATUSES.include?(status) || status >= 500)
  end

  def transient_error(error)
    TransientError.new(error.message, retry_after: retry_after_seconds(error.response_headers))
  end

  def retry_after_seconds(headers)
    value = headers.to_h.find { |key, _value| key.to_s.casecmp?("retry-after") }&.last
    return if value.blank?

    seconds = Integer(value, exception: false)
    return seconds if seconds && seconds >= 0

    delay = Time.httpdate(value.to_s) - Time.current
    delay.ceil if delay.positive?
  rescue ArgumentError
    nil
  end

  def build_hubspot_properties(hubspot_contact)
    properties = {}

    # Allowlist of writable HubSpot properties
    # country_code latitude longitude
    # (notes_last_updated is HubSpot-calculated and read-only — writing it 400s)
    writable_properties = %w[
      email
      firstname lastname
      city country
      country_code
      hs_state_code
      state
      zip
      jobtitle
      industry
      background
      timezone hs_timezone
      hs_linkedin_url bluesky_handle twitterhandle substack_handle
      member_source
      member_join_date
      joined_at
      pledged_to_vote_at
      is_member
      role
      provincial_constituency
      federal_constituency
      discord_join_date
      discord_username
      discord_display_name
      whatsapp_groups
      twitter_subscriptions substack_subscriptions
      message interests skillsets skills profession the_basics time_commitment
      work_interest about_accomplishments house_rules non_partisan_agreement
      hs_marketable_status hs_latest_source associatedcompanyid
      hs_content_membership_email_confirmed
    ]

    # Use the mapping from the model constant, only for writable properties
    HubspotContact::SYNCED_PROPERTIES.each do |local_attr, hubspot_prop|
      # Only sync properties that are in our allowlist
      next unless writable_properties.include?(hubspot_prop)

      value = hubspot_contact.send(local_attr)
      next if value.blank?

      # Handle special data type conversions for Hubspot
      case local_attr
      when :email_confirmed, :is_member, :role, :house_rules, :non_partisan_agreement
        properties[hubspot_prop] = value.to_s
      when :joined_at, :discord_join_date, :last_activity_date, :member_join_date
        # Convert datetime to ISO 8601 string for Hubspot
        properties[hubspot_prop] = value.beginning_of_day.utc.iso8601 if value.respond_to?(:iso8601)
      when :pledged_to_vote_at
        # Full timestamp — the HubSpot property is a date-time, not a date picker
        properties[hubspot_prop] = value.utc.iso8601 if value.respond_to?(:iso8601)
      when :latitude, :longitude
        properties[hubspot_prop] = value.to_s if value.present?
      else
        properties[hubspot_prop] = value.to_s
      end
    end

    # Always mark new contacts as marketing contacts when creating
    if hubspot_contact.hubspot_contact_id.blank?
      properties["hs_marketable_status"] = "true"
    end

    properties
  end
end
