class Webhooks::HubspotController < ApplicationController
  def create
    events = JSON.parse(request.body.read)
    events.each do |event|
      case event["subscriptionType"]
      when "contact.propertyChange"
        handle_contact_property_change(event)
      when "contact.creation"
        handle_contact_creation(event)
      when "contact.deletion"
        handle_contact_deletion(event)
      else
        Rails.logger.warn "Unhandled event: #{event}"
      end
    end
  end

  def handle_contact_property_change(event)
    Rails.logger.info "Handling contact property change event: #{event}"

    contact_id = event["objectId"]
    property_name = event["propertyName"]

    # Skip updates for properties we don't care about or auto-managed ones
    skip_properties = %w[
      hs_analytics_last_timestamp hs_analytics_num_page_views
      hs_email_last_email_name hs_sequences_is_enrolled
      notes_last_updated notes_last_contacted
    ]

    if skip_properties.include?(property_name)
      Rails.logger.debug "Skipping property change for #{property_name}"
      return
    end

    # Fetch the complete contact from Hubspot
    HubspotContactSyncFromWebhookJob.perform_later(contact_id, event)
  end

  def handle_contact_creation(event)
    Rails.logger.info "Handling contact creation event: #{event}"

    contact_id = event["objectId"]
    HubspotContactSyncFromWebhookJob.perform_later(contact_id, event)
  end

  def handle_contact_deletion(event)
    Rails.logger.info "Handling contact deletion event: #{event}"

    contact_id = event["objectId"]
    contact = HubspotContact.find_by(hubspot_contact_id: contact_id)

    if contact
      Rails.logger.info "Deleting contact: #{contact.email}"
      contact.destroy!
    else
      Rails.logger.warn "Contact not found for deletion: #{contact_id}"
    end
  end

  def client
    Hubspot::Client.new(access_token: Rails.application.credentials.dig(:hubspot, :access_token))
  end
end
