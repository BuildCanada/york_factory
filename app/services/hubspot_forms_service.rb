# Submits contacts through the HubSpot Forms API rather than the CRM contacts
# API, so that form-submission workflows configured in HubSpot fire. The
# submission endpoint is public (keyed by portal ID + form GUID) and needs no
# access token.
class HubspotFormsService
  SUBMIT_URL = "https://api.hsforms.com/submissions/v3/integration/submit"
  CONTACT_OBJECT_TYPE_ID = "0-1"
  DEFAULT_PORTAL_ID = "342054223"

  class ConfigurationError < StandardError; end
  class SubmissionError < StandardError; end

  def self.submit_subscriber(subscriber)
    new.submit_subscriber(subscriber)
  end

  def initialize(portal_id: default_portal_id, form_guid: default_form_guid)
    @portal_id = portal_id
    @form_guid = form_guid
  end

  def submit_subscriber(subscriber)
    if @form_guid.blank?
      raise ConfigurationError, "Set hubspot.subscriber_form_guid in Rails credentials to submit subscriber forms"
    end

    fields = {
      "email" => subscriber.email,
      "firstname" => subscriber.first_name,
      "lastname" => subscriber.last_name,
      "zip" => subscriber.postal_code
    }.compact_blank.map { |name, value| { objectTypeId: CONTACT_OBJECT_TYPE_ID, name: name, value: value } }

    response = HTTP.post("#{SUBMIT_URL}/#{@portal_id}/#{@form_guid}", json: { fields: fields })

    unless response.status.success?
      raise SubmissionError,
        "HubSpot form submission failed for #{subscriber.email}: #{response.status} #{response.body.to_s.truncate(300)}"
    end

    Rails.logger.info "Submitted HubSpot form for subscriber #{subscriber.email}"
    true
  end

  private

  def default_portal_id
    Rails.application.credentials.dig(:hubspot, :portal_id) || DEFAULT_PORTAL_ID
  end

  def default_form_guid
    Rails.application.credentials.dig(:hubspot, :subscriber_form_guid)
  end
end
