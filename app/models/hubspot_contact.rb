class HubspotContact < ApplicationRecord
  performs :sync_to_hubspot do
    rescue_from HubspotSyncService::TransientError do |error|
      if executions < HubspotSyncService::MAX_ATTEMPTS
        retry_job(wait: error.retry_after || executions**4 + 2, error: error)
      else
        raise error
      end
    end
  end

  validates :hubspot_contact_id, uniqueness: true, allow_nil: true
  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP, message: "must be a valid email address" }, uniqueness: true

  after_update :sync_to_hubspot_if_changed, if: :should_sync_to_hubspot?
  after_create :sync_to_hubspot_later, unless: :hubspot_sync_skipped?

  scope :stale, -> { where(synced_at: ..1.hour.ago).or(where(synced_at: nil)) }

  # Properties to sync between Hubspot and Rails
  SYNCED_PROPERTIES = {
    # Basic contact info
    email: "email",
    firstname: "firstname",
    lastname: "lastname",
    full_name: "full_name",
    phone: "phone",
    company: "company",
    city: "city",
    country: "country",
    zip: "zip",
    postal_code: "zip", # Map to same Hubspot field as zip
    state: "state",
    province: "state", # Map to same Hubspot field as state
    hs_state_code: "hs_state_code",
    country_code: "hs_country_region_code",
    website: "website",
    background: "background",
    industry: "industry",
    jobtitle: "jobtitle",

    # Location data
    latitude: "latitude",
    longitude: "longitude",
    timezone: "timezone",
    hs_timezone: "hs_timezone",
    ip_country: "ip_country",
    ip_city: "ip_city",
    ip_state: "ip_state",

    # Social profiles
    linkedin_url: "hs_linkedin_url",
    bluesky_handle: "bluesky_handle",
    twitter_handle: "twitterhandle",
    substack_handle: "substack_handle",

    # Membership info
    member_source: "member_source",
    joined_at: "joined_at",
    member_join_date: "member_join_date",
    is_member: "is_member",
    role: "role",
    provincial_constituency: "provincial_constituency",
    federal_constituency: "federal_constituency",
    pledged_to_vote_at: "pledged_to_vote_at",

    # Discord
    discord_join_date: "discord_join_date",
    discord_username: "discord_username",
    discord_display_name: "discord_display_name",

    # Communication preferences
    whatsapp_groups: "whatsapp_groups",
    twitter_subscriptions: "twitter_subscriptions",
    substack_subscriptions: "substack_subscriptions",
    newsletter_subscription: "newsletter_subscription",

    # Contact-specific fields
    message: "message",
    interests: "interests",
    skillsets: "skillsets",
    skills: "skills",
    profession: "profession",
    the_basics: "the_basics",
    time_commitment: "time_commitment",
    work_interest: "work_interest",
    about_accomplishments: "about_accomplishments",
    house_rules: "house_rules",
    non_partisan_agreement: "non_partisan_agreement",

    # Marketing & tracking
    hs_marketable_status: "hs_marketable_status",
    hs_latest_source: "hs_latest_source",
    hs_object_source_label: "hs_object_source_label",
    hs_object_source_detail_1: "hs_object_source_detail_1",
    associatedcompanyid: "associatedcompanyid",

    # Activity tracking
    last_activity_date: "notes_last_updated",
    num_unique_conversion_events: "num_unique_conversion_events",
    first_conversion_event_name: "first_conversion_event_name",

    # System fields
    create_date: "createdate",
    hs_createdate: "createdate", # Map to same Hubspot field as create_date
    email_confirmed: "hs_content_membership_email_confirmed"
  }.freeze

  # Helper method to get all Hubspot property names for API calls
  def self.hubspot_property_names
    SYNCED_PROPERTIES.values.uniq
  end

  # Bulk sync methods for contacts not triggered by webhooks
  def self.sync_all_from_hubspot(inline: false)
    unless inline
      return HubspotBulkSyncJob.perform_later(:all)
    end

    Rails.logger.info "Starting bulk sync of all contacts from Hubspot"
    sync_service = HubspotSyncService.new
    sync_service.sync_all_contacts_from_hubspot
  end

  def self.sync_stale_from_hubspot(inline: false)
    unless inline
      return HubspotBulkSyncJob.perform_later(:stale)
    end

    Rails.logger.info "Starting sync of stale contacts from Hubspot"
    sync_service = HubspotSyncService.new
    sync_service.sync_stale_contacts_from_hubspot
  end

  def self.sync_recent_from_hubspot(inline: false, hours: 24)
    unless inline
      return HubspotBulkSyncJob.perform_later(:recent, hours: hours)
    end

    Rails.logger.info "Starting sync of recently updated contacts from Hubspot"
    sync_service = HubspotSyncService.new
    sync_service.sync_recently_updated_contacts_from_hubspot(hours: hours)
  end

  def self.from_hubspot_properties(contact_properties)
    contact = find_or_initialize_by(hubspot_contact_id: contact_properties["hs_object_id"])

    contact.set_properties(contact_properties)

    contact
  end

  def self.upsert_hubspot_user(email:, properties: {})
    return nil if email.blank?

    # Find existing contact by email first
    contact = find_by(email: email)

    # If no local contact exists, try to find in Hubspot
    if contact.nil?
      begin
        # Search for contact in Hubspot by email
        client = Hubspot::Client.new(access_token: Rails.application.credentials.dig(:hubspot, :access_token))

        # Use the search API to find by email
        filter_groups = [
          {
            filters: [
              {
                value: email,
                propertyName: "email",
                operator: "EQ"
              }
            ]
          }
        ]

        search_request = {
          filterGroups: filter_groups,
          properties: hubspot_property_names,
          limit: 1
        }

        response = client.crm.contacts.search_api.do_search(
          public_object_search_request: search_request
        )

        if response.results&.any?
          # Contact exists in Hubspot, create local record
          hubspot_contact = response.results.first
          contact = from_hubspot_properties(hubspot_contact.properties)
        else
          # Contact doesn't exist in Hubspot, create new
          contact = new(email: email)
        end
      rescue => e
        Rails.logger.error "Error searching for contact in Hubspot: #{e.message}"
        # If search fails, create a new local contact
        contact = new(email: email)
      end
    end

    # Update contact with provided properties
    contact.assign_attributes(properties)
    contact.member_join_date ||= properties[:discord_join_date]
    # Save and sync to Hubspot
    if contact.save
      # Sync to Hubspot (will create or update based on hubspot_contact_id presence)
      contact.sync_to_hubspot
      contact
    else
      Rails.logger.error "Failed to save contact: #{contact.errors.full_messages.join(', ')}"
      nil
    end
  end

  def set_properties(contact_properties)
    attributes = {}

    SYNCED_PROPERTIES.each do |local_attr, hubspot_prop|
      value = contact_properties[hubspot_prop]
      next if value.blank?

      # Handle special data type conversions
      case local_attr
      when :create_date, :last_activity_date, :joined_at, :member_join_date, :discord_join_date, :hs_createdate, :pledged_to_vote_at
        attributes[local_attr] = parse_hubspot_timestamp(value)
      when :email_confirmed, :is_member, :role, :house_rules, :non_partisan_agreement, :newsletter_subscription
        attributes[local_attr] = value == "true"
      when :num_unique_conversion_events
        attributes[local_attr] = value.to_i if value.present?
      when :latitude, :longitude
        attributes[local_attr] = value.to_f if value.present?
      else
        attributes[local_attr] = value
      end
    end

    # Add system fields
    attributes[:raw_properties] = contact_properties.compact
    attributes[:synced_at] = Time.current

    assign_attributes(attributes)

    if postal_code_changed?
      set_constituencies
    end
  end

  def full_name
    # Use the full_name field if present, otherwise combine firstname and lastname
    super.presence || [ firstname, lastname ].compact.join(" ").presence
  end

  # Method for joined timestamp
  def joined_timestamp
    joined_at || hs_createdate || create_date || created_at
  end

  def reset_constituency_fields
    self.city = nil
    self.province = nil
    self.country_code = nil
    self.longitude = nil
    self.latitude = nil
    self.federal_constituency = nil
    self.raw_constituencies = nil
    self.country = nil
    self.hs_state_code = nil
  end

  def postal_code=(value)
    # Track if this is the first time setting a zip/postal_code value
    was_blank = zip.blank? && postal_code.blank?

    self.zip = value
    self[:postal_code] = value
    reset_constituency_fields
    set_constituencies

    # Set member_join_date if this is the first time setting a zip value
    if was_blank && value.present? && member_join_date.blank?
      self.member_join_date = Time.current
    end
  end

  def set_constituencies(force: false)
    # Use postal_code or zip field
    postal_code_value = postal_code.presence || zip.presence
    return nil unless postal_code_value.present?

    constituencies = ConstituencyService.fetch_constituencies(postal_code_value)

    if constituencies.present?
      formatted_data = ConstituencyService.format(constituencies)

      # Update the attributes
      self.city ||= formatted_data[:city] if formatted_data[:city].present?
      self.province ||= formatted_data[:province] if formatted_data[:province].present?
      self.hs_state_code ||= formatted_data[:province_code] if formatted_data[:province].present?
      self.country_code ||= formatted_data[:country_code] if formatted_data[:country_code].present?
      self.country ||= formatted_data[:country] if formatted_data[:country].present?
      self.longitude ||= formatted_data[:longitude] if formatted_data[:longitude].present?
      self.latitude ||= formatted_data[:latitude] if formatted_data[:latitude].present?
      self.federal_constituency ||= formatted_data[:federal_constituency] if formatted_data[:federal_constituency].present?
      self.provincial_constituency ||= formatted_data[:provincial_constituency] if formatted_data[:provincial_constituency].present?

      # Store raw constituencies data if there's a field for it
      self.raw_constituencies = constituencies
    end
  end

  def member_join_date
    # If member_join_date is already set, return it
    return self[:member_join_date] if self[:member_join_date].present?

    # Set member_join_date based on when zip/postal_code was first set
    set_member_join_date_from_zip_history

    self[:member_join_date]
  end

  def set_member_join_date_from_zip_history
    # Only set if member_join_date is not already set and zip/postal_code exists
    return if self[:member_join_date].present?
    return unless postal_code.present? || zip.present?

    # Try to get the date from Hubspot property history for the zip field
    member_join_date_from_hubspot = fetch_zip_property_set_date

    if member_join_date_from_hubspot
      self.member_join_date = member_join_date_from_hubspot
    else
      # Fallback to the earliest available date if we can't get property history
      fallback_date = hs_createdate || create_date || created_at
      self.member_join_date = fallback_date if fallback_date
    end
  end

  def set_member_join_date_from_discord
    # Only set if member_join_date is not already set and zip/postal_code exists
    return if self[:member_join_date].present?
    return unless postal_code.present? || zip.present?

    # Try to get the date from Hubspot property history for the zip field
    member_join_date_from_hubspot = fetch_zip_property_set_date

    if member_join_date_from_hubspot
      self.member_join_date = member_join_date_from_hubspot
    else
      # Fallback to the earliest available date if we can't get property history
      fallback_date = hs_createdate || create_date || created_at
      self.member_join_date = fallback_date if fallback_date
    end
  end

  def sync_to_hubspot
    HubspotSyncService.sync_contact_to_hubspot(self)
  end

  # Method to skip syncing when updating from webhook
  def skip_hubspot_sync!
    @skip_hubspot_sync = true
  end

  def refresh_hubspot_data
    # Use the properties defined in the model constant
    properties = HubspotContact.hubspot_property_names

    client = Hubspot::Client.new(access_token: Rails.application.credentials.dig(:hubspot, :access_token))


    hubspot_contact = client.crm.contacts.basic_api.get_by_id(
      contact_id: hubspot_contact_id,
      properties: properties
    )

    # Update the model attributes with the retrieved data
    set_properties(hubspot_contact.properties)
  end

  def fetch_subscription_types
    return nil unless email.present?

    begin
      response = HTTP.headers(
        "Authorization" => "Bearer #{Rails.application.credentials.dig(:hubspot, :access_token)}",
        "Content-Type" => "application/json"
      ).get("https://api.hubapi.com/email/public/v1/subscriptions/#{email}")

      if response.status.success?
        puts response
        data = response.parse
        data["subscriptionDefinitions"]&.map do |subscription|
          {
            id: subscription["id"],
            name: subscription["name"],
            description: subscription["description"],
            active: subscription["active"]
          }
        end
      else
        Rails.logger.error "Failed to fetch subscription types for #{email}: #{response.status} - #{response.body}"
        nil
      end
    rescue => e
      Rails.logger.error "Error fetching subscription types for #{email}: #{e.message}"
      nil
    end
  end

  def augment_properties
    set_names
    set_constituencies
  end

  def set_names
    if first_name.blank? || last_name.blank?
      derived_names = full_name.split(" ", 2)
      self.first_name = derived_names.first
      self.last_name = derived_names.last
    end
  end

  def should_sync_to_hubspot?
    # Don't sync if this update came from a webhook (to prevent loops)
    !hubspot_sync_skipped? && hubspot_contact_id.present?
  end

  def hubspot_sync_skipped?
    @skip_hubspot_sync == true
  end

  def sync_to_hubspot_if_changed
    # Only sync if any of the synced properties changed
    sync_fields = SYNCED_PROPERTIES.keys.map(&:to_s)

    if (changed & sync_fields).any?
      sync_to_hubspot_later
    end
  end

  def fetch_zip_property_set_date
    return nil unless hubspot_contact_id.present?

    begin
      # Use contacts API with propertyMode=value_and_history to get zip property history
      response = HTTP.headers(
        "Authorization" => "Bearer #{Rails.application.credentials.dig(:hubspot, :access_token)}",
        "Content-Type" => "application/json"
      ).get("https://api.hubapi.com/crm/v3/objects/contacts/#{hubspot_contact_id}", params: {
        properties: "zip",
        propertyMode: "value_and_history"
      })

      if response.status.success?
        data = response.parse
        # Get the zip property history
        zip_property = data.dig("properties", "zip")

        if zip_property && zip_property["versions"]
          # Find the earliest version where zip was set to a non-empty value
          earliest_set_version = zip_property["versions"]
            .select { |version| version["value"].present? && version["value"] != "" }
            .min_by { |version| version["timestamp"] }

          if earliest_set_version
            return parse_hubspot_timestamp(earliest_set_version["timestamp"])
          end
        end
      else
        Rails.logger.warn "Failed to fetch property history for contact #{hubspot_contact_id}: #{response.status}"
      end
    rescue => e
      Rails.logger.warn "Error fetching zip property history for contact #{hubspot_contact_id}: #{e.message}"
    end

    nil
  end

  def parse_hubspot_timestamp(timestamp_string)
    return nil if timestamp_string.blank?

    # Hubspot timestamps can be ISO 8601 strings or milliseconds
    if timestamp_string.match?(/^\d+$/)
      Time.at(timestamp_string.to_i / 1000.0)
    else
      Time.parse(timestamp_string)
    end
  rescue ArgumentError => e
    Rails.logger.warn "Failed to parse Hubspot timestamp '#{timestamp_string}': #{e.message}"
    nil
  end
end
