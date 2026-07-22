class HubspotContactSyncFromWebhookJob < ApplicationJob
  queue_as :default

  def perform(contact_id, event_data = {})
    Rails.logger.info "Syncing contact #{contact_id} from Hubspot webhook"

    begin
      # Fetch contact from Hubspot API
      client = Hubspot::Client.new(access_token: Rails.application.credentials.dig(:hubspot, :access_token))

      # Use the properties defined in the model constant
      properties = HubspotContact.hubspot_property_names

      hubspot_contact = client.crm.contacts.basic_api.get_by_id(
        contact_id: contact_id,
        properties: properties
      )

      # Create or update the contact in our database
      contact = HubspotContact.from_hubspot_properties(hubspot_contact.properties)

      # Skip syncing back to Hubspot to prevent loops
      contact.skip_hubspot_sync!

      if contact.save
        Rails.logger.info "Successfully synced contact: #{contact.email}"
      else
        Rails.logger.error "Failed to save contact: #{contact.errors.full_messages.join(', ')}"
      end

    rescue StandardError => e
      if e.code == 404
        Rails.logger.warn "Contact #{contact_id} not found in Hubspot, may have been deleted"
        # Try to delete from our database if it exists
        local_contact = HubspotContact.find_by(hubspot_contact_id: contact_id)
        local_contact&.destroy!
      else
        Rails.logger.error "Hubspot API error syncing contact #{contact_id}: #{e.message}"
        raise e
      end
    rescue StandardError => e
      Rails.logger.error "Error syncing contact #{contact_id}: #{e.message}"
      raise e
    end
  end
end
